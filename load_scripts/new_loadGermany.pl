#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use Datasources;
use WaypointTypes;

use DBLoad;
DBLoad::initialize();

my %typemap = (
	"DEM"		=>	"DME",
	"DME"		=>	"DME",
	"DVOR"		=>	"VOR",
	"DVORDME"	=>	"VOR/DME",
	"DVORTAC"	=>	"VORTAC",
	"LO"		=>	"NDB",
	"NDB"		=>	"NDB",
	"NDBDME"	=>	"NDB/DME",
	"TVOR"		=>	"TVOR",
	"TVORDME"	=>	"TVOR/DME",
	"VOR"		=>	"VOR",
	"VORDME"	=>	"VOR/DME",
	"VORTAC"	=>	"VORTAC"
);

deleteWaypointData(Datasources::DATASOURCE_GR);

while (my $fn = shift)
{
    print "doing $fn\n";
    my $fh = new IO::File($fn) or die "Airport file $fn not found";

    while (<$fh>)
    {
        chomp;

        next if ! /^Waypoint/;

        my $line = uc;

        my ($wpt, $id, $name, $ltype, $latlong, $altitude, $depth, $proximity,
             $temp, $display, $color, $symbol, $facility, $city, $state,
             $country, $datemodified, $link, $categories) =
                split("\t", $line);

        my ($ns, $latdeg, $latmin, $ew, $longdeg, $longmin) =
            ($latlong =~ /([NS])([0-9]*) ([0-9\.]*) ([EW])([0-9]*) ([0-9\.]*)/);
        my $lat = $latdeg + ($latmin / 60.0);
        my $long = $longdeg + ($longmin / 60.0);
        if ($ns eq "S")
        {
            $lat = -$lat;
        }
        if ($ew eq "E")
        {
            $long = -$long;
        }

        my $decl = getMagVar($lat, $long, 0);

        my $type = 'VFR-WP';
        my $freq = "";
        if ($symbol eq "AIRPORT")
        {
            $type = 'AIRPORT';
        }
        elsif ($symbol =~ /^NAVAID/)
        {
            my ($posid, $postype) = split("-",$id);
            if (exists($typemap{$postype}))
            {
                $type = $typemap{$postype};
                $id = $posid;
                print "name = [$name] ...";
                $name =~ s/ CH [0-9]+[XY]//;
                if ($name =~ s?^[A-Z/]+\s+??)
                {
                    if ($name =~ m/\s/)
                    {
                        ($name, $freq) = ($name =~ m/^(.*)\s(\S*)/);
                    }
                }
                print "name = [$name], freq = [$freq]\n";
            }
        }
        $id = substr($id, 0, 10);

        my $chart_map = ($type eq "VFR-WP") ? WaypointTypes::WPTYPE_VFR : 0;
        my $datasource_key = "GV_".$type."_".$id;
        insertWaypoint($id, $datasource_key, $type, $name, "",
                        "", "GM", $lat, $long, $decl, 0,
                        $freq, Datasources::DATASOURCE_GR, 1, $chart_map);
    }
    undef $fh;
}

updateDatasourceExtents(Datasources::DATASOURCE_GR);

post_load();

finish();
print "Done\n";
