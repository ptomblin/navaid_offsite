#!/usr/bin/perl -w

use DBI;
use IO::File;

use strict;

$| = 1; # for debugging

use Datasources;
use WaypointTypes;
use BoundaryConstants;
use Math::Trig;

use DBLoad;
DBLoad::initialize();

my $DAFIFdir = shift;

sub delete_DAFIF_Boundaries()
{
    deleteBoundaryData(Datasources::DATASOURCE_DAFIF);
}

sub translateAlt($)
{
    my $alt = shift;
    my $alt_limit = 0;
    my $alt_type = BoundaryConstants::ALT_TYPE_AGL;

    if ($alt =~ m/^FL([0-9]*)$/)
    {
        $alt_limit = $1;
        $alt_type = BoundaryConstants::ALT_TYPE_FLIGHT_LEVEL;
    }
    elsif ($alt =~ m/^([0-9]*)AGL$/)
    {
        $alt_limit = $1;
        $alt_type = BoundaryConstants::ALT_TYPE_AGL;
    }
    elsif ($alt =~ m/^([0-9]*)AMSL$/)
    {
        $alt_limit = $1;
        $alt_type = BoundaryConstants::ALT_TYPE_AGL;
    }
    elsif ($alt eq "SURFACE" || $alt eq "GND")
    {
        $alt_limit = 0;
        $alt_type = BoundaryConstants::ALT_TYPE_AGL;
    }
    elsif ($alt eq "U" || $alt eq "UNLTD")
    {
        $alt_limit = 9999;
        $alt_type = BoundaryConstants::ALT_TYPE_FLIGHT_LEVEL;
    }
    elsif ($alt eq "BY NOTAM")
    {
print "altitude by notam\n";
        $alt_limit = 0;
        $alt_type = BoundaryConstants::ALT_TYPE_BY_NOTAM;
    }
    else
    {
        die "Unknown altitude $alt\n";
    }
    return ($alt_limit, $alt_type);
}

sub distNMToRad($)
{
    my $nm = shift;
    return (pi/(180*60))*$nm;
}

sub distRadToNM($)
{
    my $rad = shift;
    return ((180*60)/pi)*$rad;
}

sub mod($$)
{
    my ($a, $b) = @_;
    while ($a > $b)
    {
        $a = $a - $b;
    }
    while ($a < 0)
    {
        $a = $a + $b;
    }
    return $a;
}

# Project given point (in radians) and a given distance (in radians) and a
# given angle (in radians)
sub projDistRad($$$$)
{
    my ($rlat, $rlong, $rdist, $rang) = @_;

    my $rlat1 = asin(sin($rlat)*cos($rdist)+
                    cos($rlat)*sin($rdist)*cos($rang));
    my $rlon1 = undef;
    if (cos($rlat) == 0)
    {
        $rlon1 = $rlong;
    }
    else
    {
        $rlon1 = mod($rlong - asin(sin($rang)*sin($rdist)/
                    cos($rlat1)) + pi, 2 * pi) - pi;
    }
    return ($rlat1, $rlon1);
}

sub projDistDeg($$$$)
{
    my ($lat, $lon, $dist, $ang) = @_;

    my ($rlat1, $rlon1) =  projDistRad(deg2rad($lat), deg2rad($lon),
        distNMToRad($dist), deg2rad($ang));
    return (rad2deg($rlat1), rad2deg($rlon1));
}

sub distance($$$$)
{
    my ($rlat1, $rlon1, $rlat2, $rlon2) = @_;
    
    my $d= 2*asin(sqrt((sin(($rlat1-$rlat2)/2))**2 + 
                     cos($rlat1)*cos($rlat2)*(sin(($rlon1-$rlon2)/2))**2));
    return $d;
}

# Project the given latitude and longitude (in degrees) by the given
# radius (in nm).  Returns the delta latitude (in degrees) and the delta
# longitude (in degrees)
sub projXY($$$)
{
    my ($lat, $long, $radius) = @_;

    my $radiusRad = distNMToRad($radius);

    my $deltaLat = rad2deg($radiusRad);
    my $deltaLong = rad2deg($radiusRad/cos(deg2rad($lat)));
    return ($deltaLat, $deltaLong);
}

sub course($$$$$)
{
    my ($rlat1, $rlon1, $rlat2, $rlon2, $dist) = @_;

    my $tc1 = undef;

    my $numerator = sin($rlat2)-sin($rlat1)*cos($dist);
    my $denominator  = sin($dist)*cos($rlat1);
    my $result = $numerator / $denominator;
    
    if ($result > 1)
    {
        # Thanks to rounding errors, the numerator can end up a touch more
        # than the denominator when it's really straight up and down.
        $tc1 = 0;
    }
    elsif ($result < -1)
    {
        $tc1 = pi;
    }
    elsif (sin($rlon2-$rlon1) < 0)
    {
        $tc1 = acos($result);
    }
    else
    {
        $tc1 = 2*pi-acos($result);
    }
    return $tc1;
}

sub bearing($$$$)
{
    my ($lat1, $lon1, $lat2, $lon2) = @_;

    my $rlat1 = deg2rad($lat1);
    my $rlon1 = deg2rad($lon1);
    my $rlat2 = deg2rad($lat2);
    my $rlon2 = deg2rad($lon2);

    my $dist = distance($rlat1, $rlon1, $rlat2, $rlon2);
    
    my $rbearing = course($rlat1, $rlon1, $rlat2, $rlon2, $dist);

    return rad2deg($rbearing);
}

sub updateExtents($$$)
{
    my ($extent_ref, $lat, $long) = @_;

    if (!defined($extent_ref->{min_latitude}) ||
        $extent_ref->{min_latitude} > $lat)
    {
        $extent_ref->{min_latitude} = $lat;
    }
    if (!defined($extent_ref->{min_longitude}) ||
        $extent_ref->{min_longitude} > $long)
    {
        $extent_ref->{min_longitude} = $long;
    }
    if (!defined($extent_ref->{max_latitude}) ||
        $extent_ref->{max_latitude} < $lat)
    {
        $extent_ref->{max_latitude} = $lat;
    }
    if (!defined($extent_ref->{max_longitude}) ||
        $extent_ref->{max_longitude} < $long)
    {
        $extent_ref->{max_longitude} = $long;
    }
}

# Get the real extents of an arc.
# Arguments:
# center lat/long, start lat/long/direction, end lat/long/direction, radius,
# direction ('R' for clockwise, 'L' for counter clock wise),
# extent_ref hash
# Updates extent_ref, doesn't return anything.
sub arcExtents($$$$$$$$$$$)
{
    my ($center_lat, $center_long,
        $start_lat, $start_long, $start_bearing,
        $end_lat, $end_long, $end_bearing,
        $radius, $direction, $extent_ref) = @_;

    my ($min_lat, $min_long, $max_lat, $max_long);
    if ($start_lat < $end_lat)
    {
        $min_lat = $start_lat;
        $max_lat = $end_lat;
    }
    else
    {
        $min_lat = $end_lat;
        $max_lat = $start_lat;
    }
    if ($start_long < $end_long)
    {
        $min_long = $start_long;
        $max_long = $end_long;
    }
    else
    {
        $min_long = $end_long;
        $max_long = $start_long;
    }

    updateExtents($extent_ref, $start_lat, $start_long);
    updateExtents($extent_ref, $end_lat, $end_long);

    # Convert everything to clockwise
    if ($direction eq "L")
    {
        ($start_lat, $start_long, $start_bearing,
            $end_lat, $end_long, $end_bearing) =
            ($end_lat, $end_long, $end_bearing,
                $start_lat, $start_long, $start_bearing);
    }

    my ($deltaLat, $deltaLong) = projXY($center_lat, $center_long, $radius);

    $start_bearing = mod($start_bearing, 360);
    $end_bearing = mod($end_bearing, 360);

    if ($start_bearing > $end_bearing)
    {
        $end_bearing += 360;
    }

    # All the extremes of the arc.
    if ($start_bearing < 90 && $end_bearing > 90 ||
        $start_bearing < 450 && $end_bearing > 450)
    {
        updateExtents($extent_ref, $center_lat, $center_long - $deltaLong);
    }

    if ($start_bearing < 180 && $end_bearing > 180 ||
        $start_bearing < 540 && $end_bearing > 540)
    {
        updateExtents($extent_ref, $center_lat - $deltaLat, $center_long);
    }

    if ($start_bearing < 270 && $end_bearing > 270 ||
        $start_bearing < 630 && $end_bearing > 630)
    {
        updateExtents($extent_ref, $center_lat, $center_long + $deltaLong);
    }

    if ($start_bearing < 360 && $end_bearing > 360 ||
        $start_bearing < 720 && $end_bearing > 720)
    {
        updateExtents($extent_ref, $center_lat + $deltaLat, $center_long);
    }
}

sub readBDRY($$$)
{
    my ($bdrsegh, $seg_ref, $extent_ref) = @_;

    my $line = <$bdrsegh>;

    if (!defined($line))
    {
        $seg_ref->{ident} = "Z" x 20;
        return;
    }

    chomp($line);

    my ($ident, $segment, $name, $type, $icao, $shape, $derivation,
        $wgs_lat1, $wgs_dlat1, $wgs_long1, $wgs_dlong1,
        $wgs_lat2, $wgs_dlat2, $wgs_long2, $wgs_dlong2,
        $wgs_lat0, $wgs_dlat0, $wgs_long0, $wgs_dlong0,
        $radius1, $radius2, $bearing1, $bearing2,
        $nav_ident, $nav_type, $nav_ctry, $nav_key_cd,
        $cycle_date) = split("\t", $line);
print "read bdry ident $ident, segment $segment\n";
    my $mtype = undef;
    if ($shape eq "A")
    {
        $mtype = BoundaryConstants::SEGMENT_TYPE_POINT;
    }
    elsif ($shape eq "B")
    {
        $mtype = BoundaryConstants::SEGMENT_TYPE_LINE;
    }
    elsif ($shape eq "C")
    {
        $mtype = BoundaryConstants::SEGMENT_TYPE_CIRCLE;
    }
    elsif ($shape eq "G")
    {
        $mtype = BoundaryConstants::SEGMENT_TYPE_LINE;
    }
    elsif ($shape eq "H")
    {
        $mtype = BoundaryConstants::SEGMENT_TYPE_LINE;
    }
    elsif ($shape eq "L")
    {
        $mtype = BoundaryConstants::SEGMENT_TYPE_CCW_ARC;
    }
    elsif ($shape eq "R")
    {
        $mtype = BoundaryConstants::SEGMENT_TYPE_CW_ARC;
    }

    $seg_ref->{ident} = $ident;
    $seg_ref->{segment_no} = $segment;
    $seg_ref->{type} = $mtype;
    $seg_ref->{min_latitude} = undef;
    $seg_ref->{min_longitude} = undef;
    $seg_ref->{max_latitude} = undef;
    $seg_ref->{max_longitude} = undef;
    if ($mtype eq BoundaryConstants::SEGMENT_TYPE_POINT)
    {
        die "invalid point\n" if ($wgs_dlat2 ne "" or $wgs_dlong2 ne "" or
                $wgs_dlat0 ne "" or $wgs_dlong0 ne "" or
                $wgs_dlat1 eq "" or $wgs_dlong1 eq "");
        $seg_ref->{latitude_1} = $wgs_dlat1;
        $seg_ref->{longitude_1} = -$wgs_dlong1;
        $seg_ref->{latitude_2} = undef;
        $seg_ref->{longitude_2} = undef;
        $seg_ref->{radius} = undef;
        $seg_ref->{from_bearing} = undef;
        $seg_ref->{to_bearing} = undef;
        $seg_ref->{latitude_0} = undef;
        $seg_ref->{longitude_0} = undef;

        updateExtents($seg_ref, $wgs_dlat1, -$wgs_dlong1);
    }
    elsif ($mtype eq BoundaryConstants::SEGMENT_TYPE_LINE)
    {
        # For some reason, we've got lines that have a 0 point
        #$wgs_dlat0 ne "" or $wgs_dlong0 ne "" or
        die "invalid line\n" if (
                $wgs_dlat1 eq "" or $wgs_dlong1 eq "" or
                $wgs_dlat2 eq "" or $wgs_dlong2 eq "");
        # line goes from lat/long 1 to lat/long 2
        $seg_ref->{latitude_1} = $wgs_dlat1;
        $seg_ref->{longitude_1} = -$wgs_dlong1;
        $seg_ref->{latitude_2} = $wgs_dlat2;
        $seg_ref->{longitude_2} = -$wgs_dlong2;
        $seg_ref->{radius} = undef;
        $seg_ref->{from_bearing} = undef;
        $seg_ref->{to_bearing} = undef;
        $seg_ref->{latitude_0} = undef;
        $seg_ref->{longitude_0} = undef;

        updateExtents($seg_ref, $wgs_dlat1, -$wgs_dlong1);
        updateExtents($seg_ref, $wgs_dlat2, -$wgs_dlong2);
    }
    elsif ($mtype eq BoundaryConstants::SEGMENT_TYPE_CIRCLE)
    {
        # We have records with two radii, so don't check that.
#$radius2 ne "" or
        die "invalid circle\n" if ($wgs_dlat1 ne "" or $wgs_dlong1 ne "" or
                $wgs_dlat1 ne "" or $wgs_dlong1 ne "" or
                $wgs_dlat0 eq "" or $wgs_dlong0 eq "" or $radius1 eq "");
        # lat/long 1 and 2 are undefined, 0 is the center
        $seg_ref->{latitude_1} = undef;
        $seg_ref->{longitude_1} = undef;
        $seg_ref->{latitude_2} = undef;
        $seg_ref->{longitude_2} = undef;
        $seg_ref->{radius} = $radius1;
        $seg_ref->{from_bearing} = 0;
        $seg_ref->{to_bearing} = 0;
        $seg_ref->{latitude_0} = $wgs_dlat0;
        $seg_ref->{longitude_0} = -$wgs_dlong0;

        my ($deltaLat, $deltaLong) = projXY($wgs_dlat0, -$wgs_dlong0, $radius1);
        $seg_ref->{min_latitude} = $wgs_dlat0 - $deltaLat;
        $seg_ref->{min_longitude} = -$wgs_dlong0 - $deltaLong;
        $seg_ref->{max_latitude} = $wgs_dlat0 + $deltaLat;
        $seg_ref->{max_longitude} = -$wgs_dlong0 + $deltaLong;

        updateExtents($seg_ref, $wgs_dlat0 - $deltaLat,
            -$wgs_dlong0 - $deltaLong);
        updateExtents($seg_ref, $wgs_dlat0 + $deltaLat,
            -$wgs_dlong0 + $deltaLong);
    }
    elsif ($mtype eq BoundaryConstants::SEGMENT_TYPE_CCW_ARC ||
           $mtype eq BoundaryConstants::SEGMENT_TYPE_CW_ARC)
    {
        if ($wgs_dlat0 eq "" or $wgs_dlong0 eq "")
        {
            die "no center for arc\n";
        }
        elsif ($radius1 eq "" or
                ($radius2 ne "" and $radius2 ne $radius1))
        {
            die "missing or inconsistent radii\n";
        }
        elsif ($bearing1 ne "" and $bearing2 ne "" and
                $wgs_dlat1 ne "" and $wgs_dlong1 ne "" and
                $wgs_dlat2 ne "" and $wgs_dlong2 ne "")
        {
            # The holy grail - they give all the data you need!
        }
        elsif ($bearing1 ne "" and $bearing2 ne "")
        {
            # They give the bearings, but not the end points.  Need the
            # end points for extent calculations
            ($wgs_dlat1, $wgs_dlong1) = projDistDeg(
                $wgs_dlat0,  -$wgs_dlong0, $radius1, $bearing1);
            ($wgs_dlat2, $wgs_dlong2) = projDistDeg(
                $wgs_dlat0,  -$wgs_dlong0, $radius1, $bearing2);
            # This is going to look a little stupid - later code assumes
            # these have the wrong sign, so give them the wrong sign so
            # they can be fixed later.
            $wgs_dlong1 = -$wgs_dlong1;
            $wgs_dlong2 = -$wgs_dlong2;
        }
        elsif ($bearing1 eq "" and $bearing2 eq "" and 
                $wgs_dlat1 ne "" and $wgs_dlong1 ne "" and
                $wgs_dlat2 ne "" and $wgs_dlong2 ne "")
        {
            # They give the end points, but not the bearings.  Need the
            # bearings for storing in the database.
            $bearing1 = bearing($wgs_dlat0, -$wgs_dlong0,
                    $wgs_dlat1, -$wgs_dlong1);
            $bearing2 = bearing($wgs_dlat0, -$wgs_dlong0,
                    $wgs_dlat2, -$wgs_dlong2);
        }
        else
        {
            die "inconsistent options\n";
        }
print "entering arc ($wgs_dlat0, ", -$wgs_dlong0, "), radius $radius1, ",
    " from $bearing1 to $bearing2\n";
        # lat/long 0 is center, lat/log 1 and 2 are end points
        $seg_ref->{latitude_0} = $wgs_dlat0;
        $seg_ref->{longitude_0} = -$wgs_dlong0;
        $seg_ref->{latitude_1} = $wgs_dlat1;
        $seg_ref->{longitude_1} = $wgs_dlong1;
        $seg_ref->{latitude_2} = $wgs_dlat2;
        $seg_ref->{longitude_2} = $wgs_dlong2;
        $seg_ref->{radius} = $radius1;
        $seg_ref->{from_bearing} = $bearing1;
        $seg_ref->{to_bearing} = $bearing2;

        arcExtents($wgs_dlat0, -$wgs_dlong0,
            $wgs_dlat1, $wgs_dlong1, $bearing1,
            $wgs_dlat2, $wgs_dlong2, $bearing2,
            $radius1, $mtype, $seg_ref);
    }
    updateExtents($extent_ref, $seg_ref->{min_latitude}, $seg_ref->{min_longitude});
    updateExtents($extent_ref, $seg_ref->{max_latitude}, $seg_ref->{max_longitude});
}

sub insertBDRY($$$$)
{
    my ($key, $bfh, $seg_ref, $extent_ref) = @_;

    while ($key gt $seg_ref->{ident})
    {
        $extent_ref->{min_latitude} = undef;
        $extent_ref->{min_longitude} = undef;
        $extent_ref->{max_latitude} = undef;
        $extent_ref->{max_longitude} = undef;

        readBDRY($bfh, $seg_ref, $extent_ref);
    }
    while ($key eq $seg_ref->{ident})
    {
        insertSegment($seg_ref->{ident}, $seg_ref->{segment_no},
            $seg_ref->{type},
            $seg_ref->{latitude_0}, $seg_ref->{longitude_0},
            $seg_ref->{latitude_1}, $seg_ref->{longitude_1},
            $seg_ref->{latitude_2}, $seg_ref->{longitude_2},
            $seg_ref->{radius},
            $seg_ref->{from_bearing}, $seg_ref->{to_bearing},
            $seg_ref->{min_latitude}, $seg_ref->{min_longitude},
            $seg_ref->{max_latitude}, $seg_ref->{max_longitude},
            Datasources::DATASOURCE_DAFIF);

        $extent_ref->{min_latitude} = undef;
        $extent_ref->{min_longitude} = undef;
        $extent_ref->{max_latitude} = undef;
        $extent_ref->{max_longitude} = undef;

        readBDRY($bfh, $seg_ref, $extent_ref);
    }
}

sub read_DAFIF_Boundaries($)
{
    my ($boundary_dir) = @_;

    my $bdry_par = $boundary_dir . "/BDRY_PAR.TXT";
    my $bdry     = $boundary_dir . "/BDRY.TXT";

    my $bph = new IO::File($bdry_par) or die "Boundary file $bdry_par not found";
    my $bh = new IO::File($bdry) or die "Boundary file $bdry not found";

    #   Get rid of the first line
    <$bph>;
    <$bh>;

    my %boundary_segment_rec = (
        "ident" => ""
        );
    my %extentrec = ();
    readBDRY($bh, \%boundary_segment_rec, \%extentrec);

    while (<$bph>)
    {
        chomp;
        my ($ident, $type, $name, $icao, $con_auth, $loc_hdatum, $wgs_datum,
            $comm_name, $comm_freq1, $comm_freq2, $class, $class_exc,
            $class_ex_rmk, $level, $upper_alt, $lower_alt, $rnp,
            $cycle_date) = split("\t", $_);

        # Boundary types map 1:1 to BDRY_TYPE_ constants

        my ($alt_limit_top, $alt_limit_top_type) = translateAlt($upper_alt);
        my ($alt_limit_bottom, $alt_limit_bottom_type) =
                translateAlt($lower_alt);

        insertBDRY($ident, $bh, \%boundary_segment_rec, \%extentrec);

        insertBoundary($ident, $type, $class,
                $extentrec{min_latitude}, $extentrec{min_longitude},
                $extentrec{max_latitude}, $extentrec{max_longitude},
                $name, $icao, $comm_freq1,
                $alt_limit_top, $alt_limit_top_type,
                $alt_limit_bottom, $alt_limit_bottom_type,
                Datasources::DATASOURCE_DAFIF);
    }
}

sub readSUA($$$)
{
    my ($suasegh, $seg_ref, $extent_ref) = @_;

    my $line = <$suasegh>;

    if (!defined($line))
    {
        $seg_ref->{ident} = "Z" x 20;
        return;
    }

    chomp($line);

    my ($ident, $sector, $segment, $name, $type, $icao, $shape, $derivation,
        $wgs_lat1, $wgs_dlat1, $wgs_long1, $wgs_dlong1,
        $wgs_lat2, $wgs_dlat2, $wgs_long2, $wgs_dlong2,
        $wgs_lat0, $wgs_dlat0, $wgs_long0, $wgs_dlong0,
        $radius1, $radius2, $bearing1, $bearing2,
        $nav_ident, $nav_type, $nav_ctry, $nav_key_cd,
        $cycle_date) = split("\t", $line);

    if ($sector ne "")
    {
        $ident = $ident . "\t" . $sector;
    }
print "read sua ident $ident, segment $segment\n";

    my $mtype = undef;
    if ($shape eq "A")
    {
        $mtype = BoundaryConstants::SEGMENT_TYPE_CIRCLE;
    }
    elsif ($shape eq "B")
    {
        $mtype = BoundaryConstants::SEGMENT_TYPE_LINE;
    }
    elsif ($shape eq "C")
    {
        $mtype = BoundaryConstants::SEGMENT_TYPE_CIRCLE;
    }
    elsif ($shape eq "G")
    {
        $mtype = BoundaryConstants::SEGMENT_TYPE_LINE;
    }
    elsif ($shape eq "H")
    {
        $mtype = BoundaryConstants::SEGMENT_TYPE_LINE;
    }
    elsif ($shape eq "L")
    {
        $mtype = BoundaryConstants::SEGMENT_TYPE_CCW_ARC;
    }
    elsif ($shape eq "R")
    {
        $mtype = BoundaryConstants::SEGMENT_TYPE_CW_ARC;
    }

    $seg_ref->{ident} = $ident;
    $seg_ref->{segment_no} = $segment;
    $seg_ref->{type} = $mtype;
    #if ($mtype eq BoundaryConstants::SEGMENT_TYPE_POINT)
    #{
    #    die "invalid point\n" if ($wgs_dlat2 ne "" or $wgs_dlong2 ne "" or
    #            $wgs_dlat0 eq "" or $wgs_dlong0 eq "" or
    #            $wgs_dlat1 ne "" or $wgs_dlong1 ne "");
    #    $seg_ref->{latitude_1} = $wgs_dlat0;
    #    $seg_ref->{longitude_1} = -$wgs_dlong0;
    #    $seg_ref->{latitude_2} = undef;
    #    $seg_ref->{longitude_2} = undef;
    #    $seg_ref->{radius} = undef;
    #    $seg_ref->{from_bearing} = undef;
    #    $seg_ref->{to_bearing} = undef;
#
#        updateExtents($extent_ref, $wgs_dlat1, -$wgs_dlong1);
#
#    }
    if ($mtype eq BoundaryConstants::SEGMENT_TYPE_LINE)
    {
        # For some reason, we've got lines that have a 0 point
        #$wgs_dlat0 ne "" or $wgs_dlong0 ne "" or
        die "invalid line\n" if (
                $wgs_dlat1 eq "" or $wgs_dlong1 eq "" or
                $wgs_dlat2 eq "" or $wgs_dlong2 eq "");
        $seg_ref->{latitude_1} = $wgs_dlat1;
        $seg_ref->{longitude_1} = -$wgs_dlong1;
        $seg_ref->{latitude_2} = $wgs_dlat2;
        $seg_ref->{longitude_2} = -$wgs_dlong2;
        $seg_ref->{radius} = undef;
        $seg_ref->{from_bearing} = undef;
        $seg_ref->{to_bearing} = undef;

        updateExtents($extent_ref, $wgs_dlat1, -$wgs_dlong1);
        updateExtents($extent_ref, $wgs_dlat2, -$wgs_dlong2);

    }
    elsif ($mtype eq BoundaryConstants::SEGMENT_TYPE_CIRCLE)
    {
        # We have records with two radii, so don't check that.
#$radius2 ne "" or
        die "invalid circle\n" if ($wgs_dlat1 ne "" or $wgs_dlong1 ne "" or
                $wgs_dlat1 ne "" or $wgs_dlong1 ne "" or
                $wgs_dlat0 eq "" or $wgs_dlong0 eq "" or $radius1 eq "");
        $seg_ref->{latitude_1} = $wgs_dlat0;
        $seg_ref->{longitude_1} = -$wgs_dlong0;
        $seg_ref->{latitude_2} = undef;
        $seg_ref->{longitude_2} = undef;
        $seg_ref->{radius} = $radius1;
        $seg_ref->{from_bearing} = 0;
        $seg_ref->{to_bearing} = 0;

        my ($deltaLat, $deltaLong) = projXY($wgs_dlat0, -$wgs_dlong0, $radius1);

        updateExtents($extent_ref, $wgs_dlat0 - $deltaLat,
            -$wgs_dlong0 - $deltaLong);
        updateExtents($extent_ref, $wgs_dlat0 + $deltaLat,
            -$wgs_dlong0 + $deltaLong);
    }
    elsif ($mtype eq BoundaryConstants::SEGMENT_TYPE_CCW_ARC ||
           $mtype eq BoundaryConstants::SEGMENT_TYPE_CW_ARC)
    {
        if ($wgs_dlat0 eq "" or $wgs_dlong0 eq "")
        {
            die "no center for arc\n";
        }
        elsif ($radius1 eq "" or
                ($radius2 ne "" and $radius2 ne $radius1))
        {
            die "missing or inconsistent radii\n";
        }
        elsif ($bearing1 ne "" and $bearing2 ne "" and
                $wgs_dlat1 ne "" and $wgs_dlong1 ne "" and
                $wgs_dlat2 ne "" and $wgs_dlong2 ne "")
        {
            # The holy grail - they give all the data you need!
        }
        elsif ($bearing1 ne "" and $bearing2 ne "")
        {
            # They give the bearings, but not the end points.  Need the
            # end points for extent calculations
            ($wgs_dlat1, $wgs_dlong1) = projDistDeg(
                $wgs_dlat0,  -$wgs_dlong0, $radius1, $bearing1);
            ($wgs_dlat2, $wgs_dlong2) = projDistDeg(
                $wgs_dlat0,  -$wgs_dlong0, $radius1, $bearing2);
            # This is going to look a little stupid - later code assumes
            # these have the wrong sign, so give them the wrong sign so
            # they can be fixed later.
            $wgs_dlong1 = -$wgs_dlong1;
            $wgs_dlong2 = -$wgs_dlong2;
        }
        elsif ($bearing1 eq "" and $bearing2 eq "" and 
                $wgs_dlat1 ne "" and $wgs_dlong1 ne "" and
                $wgs_dlat2 ne "" and $wgs_dlong2 ne "")
        {
            # They give the end points, but not the bearings.  Need the
            # bearings for storing in the database.
            $bearing1 = bearing($wgs_dlat0, -$wgs_dlong0,
                    $wgs_dlat1, -$wgs_dlong1);
            $bearing2 = bearing($wgs_dlat0, -$wgs_dlong0,
                    $wgs_dlat2, -$wgs_dlong2);
        }
        else
        {
            die "inconsistent options\n";
        }
print "entering arc ($wgs_dlat0, ", -$wgs_dlong0, "), radius $radius1, ",
    " from $bearing1 to $bearing2\n";
        $seg_ref->{latitude_1} = $wgs_dlat0;
        $seg_ref->{longitude_1} = -$wgs_dlong0;
        $seg_ref->{latitude_2} = undef;
        $seg_ref->{longitude_2} = undef;
        $seg_ref->{radius} = $radius1;
        $seg_ref->{from_bearing} = $bearing1;
        $seg_ref->{to_bearing} = $bearing2;

        arcExtents($wgs_dlat0, -$wgs_dlong0,
            $wgs_dlat1, $wgs_dlong1, $bearing1,
            $wgs_dlat2, $wgs_dlong2, $bearing2,
            $radius1, $mtype, $extent_ref);
    }
}

sub insertSUA($$$$)
{
    my ($key, $suafh, $seg_ref, $extent_ref) = @_;

    while ($key gt $seg_ref->{ident})
    {
        $extent_ref->{min_latitude} = undef;
        $extent_ref->{min_longitude} = undef;
        $extent_ref->{max_latitude} = undef;
        $extent_ref->{max_longitude} = undef;

        readSUA($suafh, $seg_ref, $extent_ref);
    }
    while ($key eq $seg_ref->{ident})
    {
        insertSegment($seg_ref->{ident}, $seg_ref->{segment_no},
            $seg_ref->{type},
            $seg_ref->{latitude_0}, $seg_ref->{longitude_0},
            $seg_ref->{latitude_1}, $seg_ref->{longitude_1},
            $seg_ref->{latitude_2}, $seg_ref->{longitude_2},
            $seg_ref->{radius},
            $seg_ref->{from_bearing}, $seg_ref->{to_bearing},
            $seg_ref->{min_latitude}, $seg_ref->{min_longitude},
            $seg_ref->{max_latitude}, $seg_ref->{max_longitude},
            Datasources::DATASOURCE_DAFIF);

        $extent_ref->{min_latitude} = undef;
        $extent_ref->{min_longitude} = undef;
        $extent_ref->{max_latitude} = undef;
        $extent_ref->{max_longitude} = undef;

        readSUA($suafh, $seg_ref, $extent_ref);
    }
}

sub read_DAFIF_SUAS($)
{
    my ($sua_dir) = @_;

    my $sua_par = $sua_dir . "/SUAS_PAR.TXT";
    my $sua     = $sua_dir . "/SUAS.TXT";

    my $sph = new IO::File($sua_par) or die "SUA file $sua_par not found";
    my $sh = new IO::File($sua) or die "SUA file $sua not found";

    #   Get rid of the first line
    <$sph>;
    <$sh>;

    my %sua_segment_rec = (
        "ident" => ""
        );
    my %extentrec = ();
    readSUA($sh, \%sua_segment_rec, \%extentrec);

    while (<$sph>)
    {
        chomp;
        my ($ident, $sector, $type, $name, $icao, $con_agcy, $loc_hdatum,
            $wgs_datum, $comm_name, $comm_freq1, $comm_freq2, $level,
            $upper_alt, $lower_alt, $eff_times, $wx, $cycle_date,
            $eff_date) = split("\t", $_);

        if ($sector ne "")
        {
            $ident = $ident . "\t" . $sector;
        }

        my $atype = undef;
        if ($type eq "A")
        {
            $atype = BoundaryConstants::BDRY_TYPE_ALERT;
        }
        elsif ($type eq "D")
        {
            $atype = BoundaryConstants::BDRY_TYPE_DANGER;
        }
        elsif ($type eq "M")
        {
            $atype = BoundaryConstants::BDRY_TYPE_MOA;
        }
        elsif ($type eq "P")
        {
            $atype = BoundaryConstants::BDRY_TYPE_PROHIBITED;
        }
        elsif ($type eq "R")
        {
            $atype = BoundaryConstants::BDRY_TYPE_RESTRICTED;
        }
        elsif ($type eq "T")
        {
            $atype = BoundaryConstants::BDRY_TYPE_TEMPORARY;
        }
        elsif ($type eq "W")
        {
            $atype = BoundaryConstants::BDRY_TYPE_WARNING;
        }
        die "Invalid type" if (!defined($atype));

        my ($alt_limit_top, $alt_limit_top_type) = translateAlt($upper_alt);
        my ($alt_limit_bottom, $alt_limit_bottom_type) =
                translateAlt($lower_alt);

        insertSUA($ident, $sh, \%sua_segment_rec, \%extentrec);

        insertBoundary($ident, $atype, undef,
                $extentrec{min_latitude}, $extentrec{min_longitude},
                $extentrec{max_latitude}, $extentrec{max_longitude},
                $name, $icao, $comm_freq1,
                $alt_limit_top, $alt_limit_top_type,
                $alt_limit_bottom, $alt_limit_bottom_type,
                Datasources::DATASOURCE_DAFIF);
    }
}

my $DAFIFbdrydir = $DAFIFdir . "/BDRY";
my $DAFIFsuadir = $DAFIFdir . "/SUAS";

print "deleting DAFIF data\n";
delete_DAFIF_Boundaries();

print "loading DAFIF boundaries\n";
read_DAFIF_Boundaries($DAFIFbdrydir);
print "loading DAFIF SUAs\n";
read_DAFIF_SUAS($DAFIFsuadir);

print "Done\n";
finish();

