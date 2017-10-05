#
#	This file provides functions that CoPilot and other database generators
#	can use.
#
#
#   This file is copyright (c) 2001 by Paul Tomblin, and may be distributed
#   under the terms of the "Clarified Artistic License", which should be
#   bundled with this file.  If you recieve this file without the Clarified
#   Artistic License, email ptomblin@xcski.com and I will mail you a copy.
#

=head1 NAME

WaypointDB - Helper functions for waypoint generators

=head1 SYNOPSIS

    use WaypointDB;

    my $conn = WaypointDB::connectDB;

=head1 DESCRIPTION

The WaypointDB is a helper class for waypoint generators.

=cut

package WaypointDB;

@ISA = 'Exporter';
@EXPORT = qw(connectDB getSessionId getOrCreateSessionId
printDatasources
formExtents putExtents putFormExtents passOnExtents getExtents
formCSP putCSP putFormCSP passOnCSP getCSP
formNotes putNotes putFormNotes passOnNotes getNotes
formGNotes putGNotes putGFormNotes passOnGNotes getGNotes
formDatasources putDatasources putFormDatasources passOnDatasources
getDatasources
formTypes putTypes putFormTypes passOnTypes getTypes
formCharts putCharts putFormCharts passOnCharts getCharts
formDetails putDetails putFormDetails passOnDetails getDetails
startGeneratorProcess startGeneratorProcess2);

use strict;
#use CGI::Fast;
#use CGI;
use DBI;
use WPInfo;
use Digest::MD5 qw(md5_hex);
use POSIX qw(setsid);

use constant EXPIRE => 365;  # allow 1 years before expiration
use constant COOKIE_NAME => 'SessionId';
use constant SECRET => "MyCoPilotSecret";
use constant MAX_TRIES => 10;
use constant DO_CACHE => 0;

use vars qw($ID_LENGTH);
$ID_LENGTH             = 8;

use vars qw(%countries %country_codes %states %provinces);
%countries = ();
%country_codes = ();
%states = ();
%provinces = ();

use vars qw(%type_categories);
%type_categories = ();

use vars qw(%map_categories);
%map_categories = ();

# Convert this to an array some time
use vars qw(%datasources);
%datasources = ();

sub connectDB()
{
    my $conn;
    $conn = DBI->connect(
            "DBI:mysql:database=navaid",
            "ptomblin", "2nafish2") or die $conn->errstr;
    $conn->{"AutoCommit"} = 0;
    return ($conn, $conn);
}

use constant Category_Airports => 1;
use constant Category_Navaids => 2;
use constant Category_Intersections => 3;

my ($sess_conn, $wp_conn) = connectDB();


# Get the list of countries
my $result = $wp_conn->prepare(
            "SELECT     max_lat, min_lat, max_long, " .
            "           min_long, country " .
            "FROM       country_extents ") or die $wp_conn->errstr;
$result->execute();
my @row;
while (@row = $result->fetchrow_array)
{
    my ($max_lat, $min_lat, $max_long, $min_long, $country) = @row;
    $countries{$country} = {"max_long" => $max_long,
            "min_long" => $min_long,
            "max_lat" => $max_lat,
            "min_lat" => $min_lat};
}

# Get the list of ICAO country codes
$result = $sess_conn->prepare(
    "SELECT     code, country_name " .
    "FROM       dafif_country_codes");
$result->execute();
while (@row = $result->fetchrow_array)
{
    my $id = $row[0];
    $country_codes{$id} = $row[1];
#   $country_codes{$id} =~ s/'/''/g;
}

$result = $wp_conn->prepare(
            "SELECT     max_lat, min_lat, max_long, min_long, " .
            "           state " .
            "FROM       state_country_extents " .
            "WHERE      country = 'CA'");
$result->execute();

# Get the list of provinces
while (@row = $result->fetchrow_array)
{
    my ($max_lat, $min_lat, $max_long, $min_long, $province) = @row;
    $provinces{$province} = {"max_long" => $max_long,
            "min_long" => $min_long,
            "max_lat" => $max_lat,
            "min_lat" => $min_lat};
}

#open(DEBUG,">>/home/ptomblin/tmp/waypoint.out");

$result = $sess_conn->prepare(
            "SELECT     code, long_name " .
            "FROM       state_prov_lookup " .
            "WHERE      country = 'CA' ");
$result->execute();

# Get the list of provinces names
while (@row = $result->fetchrow_array)
{
    my ($province, $long_name) = @row;
    if (defined($provinces{$province}))
    {
        $provinces{$province}->{"long_name"} = $long_name;
    }
    if (defined($provinces{$province."-E"}))
    {
        $provinces{$province."-E"}->{"long_name"} = $long_name;
    }
    if (defined($provinces{$province."-W"}))
    {
        $provinces{$province."-W"}->{"long_name"} = $long_name;
    }
}

$result = $wp_conn->prepare(
            "SELECT     max_lat, min_lat, max_long, min_long, " .
            "           state " .
            "FROM       state_country_extents " .
            "WHERE      country = 'US'");
$result->execute();
# Get the list of states
while (@row = $result->fetchrow_array)
{
    my ($max_lat, $min_lat, $max_long, $min_long, $state) = @row;
    $states{$state} = {"max_long" => $max_long,
            "min_long" => $min_long,
            "max_lat" => $max_lat,
            "min_lat" => $min_lat};
}

$result = $sess_conn->prepare(
            "SELECT     code, long_name " .
            "FROM       state_prov_lookup " .
            "WHERE      country = 'US' ");
$result->execute();

# Get the list of states names
while (@row = $result->fetchrow_array)
{
    my ($state, $long_name) = @row;
    if (defined($states{$state}))
    {
        $states{$state}->{"long_name"} = $long_name;
    }
    if (defined($states{$state."-E"}))
    {
        $states{$state."-E"}->{"long_name"} = $long_name;
    }
    if (defined($states{$state."-W"}))
    {
        $states{$state."-W"}->{"long_name"} = $long_name;
    }
}

#close DEBUG;

# Get the list of waypoint types 
$result = $sess_conn->prepare(
            "SELECT     type, category, selected_by_default " .
            "FROM       type_categories");
$result->execute();
while (@row = $result->fetchrow_array)
{
  my ($type, $category, $selected_by_default) = @row;
  $type_categories{$type} = {
        "type" => $type,
        "category" => $category, 
        "selected_by_default" => $selected_by_default
  };
}


# Get the list of chart types 
$result = $sess_conn->prepare(
            "SELECT     type, longname, selected_by_default " .
            "FROM       map_categories");
$result->execute();
while (@row = $result->fetchrow_array)
{
  my ($type, $longname, $selected_by_default) = @row;
  $map_categories{$type} = {
        "type" => $type,
        "longname" => $longname, 
        "selected_by_default" => $selected_by_default
  };
}

# Get the list of data sources
$result = $wp_conn->prepare(
            "SELECT     ds_index, source_name, source_long_name, " .
            "           source_url, credit, available_types, updated, " . 
            "           min_lat, min_long, max_lat, max_long " . 
            "FROM       datasource " .
            "ORDER BY   ds_index");
$result->execute();
while (@row = $result->fetchrow_array)
{
  my $index = $row[0];
  $datasources{$index} = {
              "index" => $index,
              "source_name" => $row[1],
              "source_long_name" => $row[2],
              "source_url" => (defined($row[3]) ? $row[3] : ""),
              "credit" => $row[4],
              "available_types" => $row[5],
              "updated" => $row[6],
              "min_lat" => $row[7],
              "min_long" => $row[8],
              "max_lat" => $row[9],
              "max_long" => $row[10]
  };
}

$wp_conn->commit();
$wp_conn->disconnect();
#$sess_conn->disconnect();

undef $wp_conn;
undef $sess_conn;

# Gets the session id, returns null if not found.
sub getSessionId($)
{
    my ($cg) = @_;

    my $sessionId = $cg->cookie(-name => COOKIE_NAME);

    return $sessionId;
}

# generate a hash value
sub generateSessionHash ($)
{
    my $value = shift;
    return substr(md5_hex($value), 0, $ID_LENGTH);
}

sub expireOldSessions($)
{
    my ($sess_conn) = @_;
}

# Gets the session id, creates a new one if not found.
sub getOrCreateSessionId($$$)
{
    my ($cg, $sess_conn, $prog) = @_;
#open(DEBUG,">>/www/navaid.com/tmp/waypoint.out");
#print DEBUG "getOrCreateSessionId called, prog = $prog\n";

    expireOldSessions($sess_conn);

    my $sessionId = getSessionId($cg);

    my $ip = $cg->remote_host();
#print DEBUG "sessionId = $sessionId, ip = $ip\n";

    if (defined($sessionId))
    {
        my @row;

        my $result = $sess_conn->prepare(
            "SELECT     session_id " .
            "FROM       sess_main " .
            "WHERE      session_id = ?");
        $result->execute($sessionId) or die $sess_conn->errstr;
        if (@row = $result->fetchrow_array)
        {
#print DEBUG "found the session id already\n";
            $result = $sess_conn->prepare(
                "UPDATE     sess_main " .
                "SET        updatedate = CURRENT_DATE, " .
                "           ip = ? " .
                "WHERE      session_id = ?");
            $result->execute($ip, $sessionId);
        }
        else
        {
#print DEBUG "expired session id?\n";
            #   The select didn't find anything, so the session id isn't
            #   there!  It must have expired, but the cookie didn't.  If I
            #   insert it in, I might conflict with some other session id that
            #   was created after this one expired out of the database.
            undef $sessionId;
        }
    }

    if (!defined($sessionId))
    {
        # generate a session id and save it in the database
        my $tries = 0;
        $sessionId = generateSessionHash(SECRET . rand());

        while ($tries++ < MAX_TRIES)
        {
#print DEBUG "sessionId = $sessionId\n";
            my $result = $sess_conn->prepare(
                "INSERT INTO    sess_main " .
                "   (session_id, updatedate, entered_date, prog, ip) " .
                "VALUES         (?, CURRENT_DATE, CURRENT_DATE, ?, ?)");
            my $rs = $result->execute($sessionId, $prog, $ip);
#print DEBUG "rs = $rs, errstr = ", $sess_conn->errstr, "\n";
            last if ($rs == 1);

            $sessionId = generateSessionHash($sessionId);
        }

        return (undef, undef) if $tries >= MAX_TRIES;  # we failed
    }
#print DEBUG "setting cookie with sessionId = $sessionId\n";

    $sess_conn->commit;

    my $cookie = $cg->cookie(-name=> COOKIE_NAME,
            -value=>$sessionId,
            -path=>'/',
            -expires=>"+" . EXPIRE . "d");
#print DEBUG "cookie = $cookie\n";
#close DEBUG;
    return ($sessionId, $cookie);
}

sub printDatasources($)
{
    my $cg = shift;

    print(
        $cg->hr() . "\n" .
        $cg->h1('Data Sources') . "\n");

    print(<<EOF);
<TABLE border=0>
  <TR>
    <TH align=left>Data Source</TH>
    <TH align=left>Last Updated</TH>
    <TH align=left>From:</TH>
  </TR>
EOF
    my $index;
    foreach $index (sort { $a <=> $b} (keys(%WaypointDB::datasources)))
    {
        my $ref = $WaypointDB::datasources{$index};
        my $name = $ref->{source_name};
        if (defined($ref->{updated}) && $ref->{updated})
        {
            print("<TR><TD>" . $name . "</TD><TD>" .
                    $ref->{updated} . "</TD><TD>" .
                    $ref->{source_url} .
                    "</TD></TR>\n");
            print("<TR><TD COLSPAN=2>" . $ref->{source_long_name} .
                    "</TD><TD>" .
                    $ref->{credit} .  "</TD></TR><tr><td>&nbsp; </td></tr>\n");
        }
    }
    print("</TABLE>\n");
    print("For more information about these datasources\n");
    print('<a href="/datasources.html">click here</a>');
    print("\n");
}


sub formExtents($$$)
{
    my ($sessionId, $cg, $sess_conn) = @_;

    my ($min_long, $min_lat, $max_long, $max_lat,
        $nw_quad, $sw_quad, $ne_quad, $se_quad);

    if (!defined($sessionId))
    {
        ($min_long, $min_lat, $max_long, $max_lat,
            $nw_quad, $sw_quad, $ne_quad, $se_quad) =
            (undef, undef, undef, undef, 0, 0, 0, 0);
    }
    else
    {
        my $result = $sess_conn->prepare(
            "SELECT     min_longitude, min_latitude, max_longitude, " .
            "           max_latitude, nw_quad, sw_quad, ne_quad, se_quad ".
            "FROM       sess_main ".
            "WHERE      session_id = ?");
        $result->execute($sessionId);
        my @row = $result->fetchrow_array;
        ($min_long, $min_lat, $max_long, $max_lat,
            $nw_quad, $sw_quad, $ne_quad, $se_quad) = @row;
    }

    my $min_lat_ns = 'N';
    if (defined($min_lat) && $min_lat < 0)
    {
        $min_lat_ns = 'S';
        $min_lat = 0 - $min_lat;
    }

    my $max_lat_ns = 'N';
    if (defined($max_lat) && $max_lat < 0)
    {
        $max_lat_ns = 'S';
        $max_lat = 0 - $max_lat;
    }

    my $min_long_ew = 'W';
    if (defined($min_long) && $min_long < 0)
    {
        $min_long_ew = 'E';
        $min_long = 0 - $min_long;
    }

    my $max_long_ew = 'W';
    if (defined($max_long) && $max_long < 0)
    {
        $max_long_ew = 'E';
        $max_long = 0 - $max_long;
    }

    if (!defined($min_lat))
    {
        $min_lat = "";
    }
    if (!defined($min_long))
    {
        $min_long = "";
    }
    if (!defined($max_lat))
    {
        $max_lat = "";
    }
    if (!defined($max_long))
    {
        $max_long = "";
    }

    print(<<EOF);
<h2>Geographic Area</h2>
<table border="2" width="95%">
<tr><th>&nbsp;</th><th>Minimum<br>(decimal degrees
NN.NNN)</th><th>Maximum<br>(decimal degrees NN.NNN)</th></tr>
<!-- <tr><th>&nbsp;</th><th>(decimal degrees NN.NNN)</th><th>(decimal degrees
NN.NNN)</th></tr> -->
<tr>
  <td>Latitude</td>
  <td><input type="text" name="min_lat" value="$min_lat">
      <select name="min_lat_ns">
EOF
    print('<option value="N"' .  ($min_lat_ns eq 'N'? " selected":"") .
            ">North\n");
    print('<option value="S"' .  ($min_lat_ns eq 'S'? " selected":"") .
            ">South\n");
    print(<<EOF);
      </select>
  </td>
  <td><input type="text" name="max_lat" value="$max_lat">
      <select name="max_lat_ns">
EOF
    print('<option value="N"' .  ($max_lat_ns eq 'N'? " selected":"") .
            ">North\n");
    print('<option value="S"' .  ($max_lat_ns eq 'S'? " selected":"") .
            ">South\n");
    print(<<EOF);
      </select>
  </td>
</tr>
<tr>
  <td>Longitude</td>
  <td><input type="text" name="min_long" value="$min_long">
      <select name="min_long_ew">
EOF
    print('<option value="W"' .  ($min_long_ew eq 'W'? " selected":"") .
            ">West\n");
    print('<option value="E"' .  ($min_long_ew eq 'E'? " selected":"") .
            ">East\n");
    print(<<EOF);
      </select>
  </td>
  <td><input type="text" name="max_long" value="$max_long">
      <select name="max_long_ew">
EOF
    print('<option value="W"' .  ($max_long_ew eq 'W'? " selected":"") .
            ">West\n");
    print('<option value="E"' .  ($max_long_ew eq 'E'? " selected":"") .
            ">East\n");
    print(<<EOF);
      </select>
  </td>
</tr>
</table>
<h2>Quadrants</h2>
<table border="2" width="95%">
<tr>
EOF
    if (!defined($nw_quad))
    {
        $nw_quad = 0;
    }
    if (!defined($ne_quad))
    {
        $ne_quad = 0;
    }
    if (!defined($sw_quad))
    {
        $sw_quad = 0;
    }
    if (!defined($se_quad))
    {
        $se_quad = 0;
    }


    print(
  '<td><input type="checkbox" name="nw_quad" value="y"' .
  (($nw_quad)?" CHECKED":"") . ">North West\n");
    print(<<EOF);
  (including North America)</td>
</tr>
<tr>
EOF
    print(
  '<td><input type="checkbox" name="sw_quad" value="y"' .
  (($sw_quad)?" CHECKED":"") . ">South West\n");
    print(<<EOF);
  (including South America)</td>
</tr>
<tr>
EOF
    print(
  '<td><input type="checkbox" name="ne_quad" value="y"' .
  (($ne_quad)?" CHECKED":"") . ">North East\n");
    print(<<EOF);
  (including (most of) Europe and Asia)</td>
</tr>
<tr>
EOF
    print(
  '<td><input type="checkbox" name="se_quad" value="y"' .
  (($se_quad)?" CHECKED":"") . ">South East\n");
    print(<<EOF);
  (including Africa, Australia and the Pacific islands)</td>
</tr>
</table>
EOF
}

sub putExtents($$$)
{
    my ($sessionId, $sess_conn, $cg) = @_;
#open(DEBUG,">>/home/ptomblin/tmp/waypoint.out");
#print DEBUG "putExtents($sessionId, $sess_conn, $cg) called\n";

    my ($cmin_long, $min_long_ew, $cmin_lat, $min_lat_ns,
        $cmax_long, $max_long_ew, $cmax_lat, $max_lat_ns) = 
       ($cg->param("min_long"), $cg->param("min_long_ew"),
        $cg->param("min_lat"), $cg->param("min_lat_ns"),
        $cg->param("max_long"), $cg->param("max_long_ew"),
        $cg->param("max_lat"), $cg->param("max_lat_ns"));
    my $nw_quad = $cg->param("nw_quad") || 0;
    my $sw_quad = $cg->param("sw_quad") || 0;
    my $ne_quad = $cg->param("ne_quad") || 0;
    my $se_quad = $cg->param("se_quad") || 0;

    my ($min_long, $min_lat, $max_long, $max_lat) = (0, 0, 0, 0);

    if ($nw_quad eq "y")
    {
        $max_lat = 90.0;
        $max_long = 180.0;
        $nw_quad = 1;
    }
    else
    {
        $nw_quad = 0;
    }
    if ($ne_quad eq "y")
    {
        $max_lat = 90.0;
        $min_long = -180.0;
        $ne_quad = 1;
    }
    else
    {
        $ne_quad = 0;
    }
    if ($sw_quad eq "y")
    {
        $min_lat = -90.0;
        $max_long = 180.0;
        $sw_quad = 1;
    }
    else
    {
        $sw_quad = 0;
    }
    if ($se_quad eq "y")
    {
        $min_lat = -90.0;
        $min_long = -180.0;
        $se_quad = 1;
    }
    else
    {
        $se_quad = 0;
    }

    if (defined($cmin_lat))
    {
        $cmin_lat =~ s/\s+//g;
        if ($cmin_lat ne "")
        {
            if ($cmin_lat =~ m/^\d*(\.\d*)?$/)
            {
                $min_lat = $cmin_lat;
                if ($min_lat_ns eq "S")
                {
                    $min_lat = 0 - $min_lat;
                    $cmin_lat = $min_lat;
                }
            }
            else
            {
                return (0, undef, undef, undef, undef);
            }
        }
        else
        {
            undef $cmin_lat;
        }
    }

    if (defined($cmin_long))
    {
        $cmin_long =~ s/\s+//g;
        if ($cmin_long ne "")
        {
            if ($cmin_long =~ m/^\d*(\.\d*)?$/)
            {
                $min_long = $cmin_long;
                if ($min_long_ew eq "E")
                {
                    $min_long = 0 - $min_long;
                    $cmin_long = $min_long;
                }
            }
            else
            {
                return (0, undef, undef, undef, undef);
            }
        }
        else
        {
            undef $cmin_long;
        }
    }

    if (defined($cmax_lat))
    {
        $cmax_lat =~ s/\s+//g;
        if ($cmax_lat ne "")
        {
            if ($cmax_lat =~ m/^\d*(\.\d*)?$/)
            {
                $max_lat = $cmax_lat;
                if ($max_lat_ns eq "S")
                {
                    $max_lat = 0 - $max_lat;
                    $cmax_lat = $max_lat;
                }
            }
            else
            {
                return (0, undef, undef, undef, undef);
            }
        }
        else
        {
            undef $cmax_lat;
        }
    }

    if (defined($cmax_long))
    {
        $cmax_long =~ s/\s+//g;
        if ($cmax_long ne "")
        {
            if ($cmax_long =~ m/^\d*(\.\d*)?$/)
            {
                $max_long = $cmax_long;
                if ($max_long_ew eq "E")
                {
                    $max_long = 0 - $max_long;
                    $cmax_long = $max_long;
                }
            }
            else
            {
                return (0, undef, undef, undef, undef);
            }
        }
        else
        {
            undef $cmax_long;
        }
    }

    if ($max_long == 0.0 && $min_long == 0.0)
    {
        $max_long = 180.0;
        $min_long = -180.0;
    }
    if ($max_lat == 0.0 && $min_lat == 0.0)
    {
        $max_lat = 90.0;
        $min_lat = -90.0;
    }
    if ($max_lat < $min_lat)
    {
        my $temp = $max_lat;
        $max_lat = $min_lat;
        $min_lat = $temp;
    }
    if ($max_long < $min_long)
    {
        my $temp = $max_long;
        $max_long = $min_long;
        $min_long = $temp;
    }

    if ($max_long > 181.0 ||
        $min_long < -181.0 ||
        $max_lat > 91.0 ||
        $min_lat < -91.0)
    {
        return (0, undef, undef, undef, undef);
    }

    if (defined($sessionId))
    {
#print DEBUG "sessionId = '$sessionId'\n";
#print DEBUG "min = ($cmin_long, $cmin_lat), max = ($cmax_long, $cmax_lat)\n";
#print DEBUG "nw_quad = $nw_quad, sw_quad = $sw_quad, ne_quad = $ne_quad, se_quad = $se_quad\n";
        my $result = $sess_conn->prepare(
            "UPDATE     sess_main " .
            "SET        min_longitude = ?, " .
            "           min_latitude = ?, " .
            "           max_longitude = ?, " .
            "           max_latitude = ?, " .
            "           nw_quad = ?, " .
            "           sw_quad = ?, " .
            "           ne_quad = ?, " .
            "           se_quad = ? " .
            "WHERE      session_id = ?");
        my $rs = $result->execute(
            $cmin_long, $cmin_lat, $cmax_long, $cmax_lat, 
            $nw_quad, $sw_quad, $ne_quad, $se_quad,
            $sessionId);
#print DEBUG "rs = $rs\n";

        if ($rs != 1 && $rs != 0)
        {
#print DEBUG "bad rs = $rs\n";
#close DEBUG;
            return (0, undef, undef, undef, undef);
        }
        $sess_conn->commit;
    }
#print DEBUG "putExtents done\n";
#close DEBUG;

    return (1, $min_lat, $min_long, $max_lat, $max_long);
}

sub putFormExtents($$$$)
{
    my ($min_lat, $min_long, $max_lat, $max_long) = @_;
    print(<<EOF);
<input type="hidden" name="min_lat" value="$min_lat">
<input type="hidden" name="min_long" value="$min_long">
<input type="hidden" name="max_lat" value="$max_lat">
<input type="hidden" name="max_long" value="$max_long">
EOF
}

sub passOnExtents($)
{
    my ($cg) = @_;
    print(
        $cg->hidden('min_lat', $cg->param('min_lat')) . "\n" .
        $cg->hidden('min_long', $cg->param('min_long')) . "\n" .
        $cg->hidden('max_lat', $cg->param('max_lat')) . "\n" .
        $cg->hidden('max_long', $cg->param('max_long')) . "\n");
}

sub getExtents($)
{
    my ($cg) = @_;
    return ($cg->param("min_lat"),
            $cg->param("min_long"),
            $cg->param("max_lat"),
            $cg->param("max_long"));
}

sub formCSP($$$$$$$)
{
    my ($sessionId, $cg, $sess_conn,
        $min_lat, $min_long, $max_lat, $max_long) = @_;
    my (@usedCountries, @usedStates, @usedProvinces);
    @usedCountries = ();
    @usedStates = ();
    @usedProvinces = ();
    if (defined($sessionId))
    {
        my $result = $sess_conn->prepare(
            "SELECT     country " .
            "FROM       sess_country ".
            "WHERE      session_id = ?");
        $result->execute($sessionId);
        my @row;
        while (@row = $result->fetchrow_array)
        {
            push @usedCountries, $row[0];
        }
        $result = $sess_conn->prepare(
            "SELECT     state " .
            "FROM       sess_state ".
            "WHERE      session_id = ?");
        $result->execute($sessionId);
        while (@row = $result->fetchrow_array)
        {
            push @usedStates, $row[0];
        }
        $result = $sess_conn->prepare(
            "SELECT     province " .
            "FROM       sess_province ".
            "WHERE      session_id = ?");
        $result->execute($sessionId);
        while (@row = $result->fetchrow_array)
        {
            push @usedProvinces, $row[0];
        }
    }

    print($cg->h2('All') . "\n");
    print(<<EOF);
<p>If you choose this option, you don't need to make any choices in
"Countries" or "States" or "Provinces".
<br>
EOF
    my $checked = 
        ((scalar(@usedCountries) < 1) &&
         (scalar(@usedStates) < 1) &&
         (scalar(@usedProvinces) < 1));
    print('<table border="2" width="95%"><tr><td>' . "\n");
    print($cg->checkbox(-name=>'all',
                            -value=>'All',
                            -label=>'All Locations',
                            -checked=>$checked));
    print("</td></tr></table>");

    print($cg->h2('Countries') . "\n");
    my $i = 0;
    my $hadUSA = 0;
    my $hadCanada = 0;
    print('<table border="2" width="95%"><tr>' . "\n");
    my $lastCountry = "";
    foreach my $country (sort(keys(%countries)))
    {
        my $cref = $countries{$country};
        if ($cref->{"max_lat"} < $min_lat ||
            $cref->{"min_lat"} > $max_lat ||
            $cref->{"max_long"} < $min_long ||
            $cref->{"min_long"} > $max_long)
        {
            next;
        }

        $country =~ s/-[WE]//;
        next if ($country eq $lastCountry);
        $lastCountry = $country;

        if ($country eq "US")
        {
            $hadUSA = 1;
        }

        if ($country eq "CA")
        {
            $hadCanada = 1;
        }

        my $countrycheck = scalar(grep (/^$country$/, @usedCountries));

        my $cname = $country_codes{$country} . " ($country)";
        print("<td>" . $cg->checkbox(-name=>'countries',
                                -value=>$country,
                                -label=>" $cname",
                                -checked=>$countrycheck) . "</td>");
        if (($i % 3) == 2)
        {
            print("</tr><tr>");
        }
        $i++;
    }
    print("</tr></table>");

    if ($hadUSA)
    {
        print($cg->h2('States') . "\n");
        my $state;
        $i = 1;
        print('<table border="2" width="95%"><tr><td>' . "\n");

        # Always include the "No State" location.

        my $statecheck = scalar(grep (/^$/, @usedStates));

        print($cg->checkbox(-name=>'states',
                    -value=>"No State",
                    -label=>"No State",
                    -checked=>$statecheck));
        print("</td>");

        my $lastState = "";

        foreach $state (sort(keys(%states)))
        {
            my $sref = $states{$state};
            if ($sref->{"max_lat"} < $min_lat ||
                $sref->{"min_lat"} > $max_lat ||
                $sref->{"max_long"} < $min_long ||
                $sref->{"min_long"} > $max_long)
            {
                next;
            }

            $state =~ s/-[WE]//;
            next if ($state eq "");
            next if ($state eq $lastState);
            $lastState = $state;


            $statecheck = scalar(grep (/^$state$/, @usedStates));

            my $cname = $sref->{long_name} . " ($state)";

            print("<td>" . $cg->checkbox(-name=>'states',
                                    -value=>$state,
                                    -label=>$cname,
                                    -checked=>$statecheck) . "</td>");
            if (($i % 3) == 2)
            {
                print("</tr><tr>");
            }
            $i++;
        }
        print("</tr></table>");
    }

    if ($hadCanada)
    {
        print($cg->h2('Provinces') . "\n");
        my $province;
        $i = 1;
        print('<table border="2" width="95%"><tr><td>' . "\n");

        my $provincecheck = scalar(grep (/^$/, @usedProvinces));

        # Always include the "No Province" case.
        print($cg->checkbox(-name=>'provinces',
                    -value=>"No Province",
                    -label=>"No Province",
                    -checked=>$provincecheck));

        print("</td>");
        my $lastProvince = "";

        foreach $province (sort(keys(%provinces)))
        {
            my $pref = $provinces{$province};
            if ($pref->{"max_lat"} < $min_lat ||
                $pref->{"min_lat"} > $max_lat ||
                $pref->{"max_long"} < $min_long ||
                $pref->{"min_long"} > $max_long)
            {
                next;
            }

            next if ($province eq "");

            $province =~ s/-[WE]//;
            next if ($province eq $lastProvince);
            $lastProvince = $province;

            $provincecheck = scalar(grep (/^$province$/, @usedProvinces));

            my $cname = $pref->{long_name} . " ($province)";

            print("<td>" . $cg->checkbox(-name=>'provinces',
                                    -value=>$province,
                                    -label=>$cname,
                                    -checked=>$provincecheck) . "</td>");
            if (($i % 3) == 2)
            {
                print("</tr><tr>");
            }
            $i++;
        }
        print("</tr></table>");
    }
}

sub putCSP($$$)
{
    my ($sessionId, $sess_conn, $cg) = @_;

    my @countries = $cg->param("countries");
    my @states = $cg->param("states");
    my @provinces = $cg->param("provinces");
    my @all = $cg->param("all");

    my $allused = scalar(@all) > 0;
    my $countriesused = scalar(@countries) > 0;
    my $statesused = scalar(@states) > 0;
    my $provincesused = scalar(@provinces) > 0;

    # If somebody selected "ALL" and something else, or they selected
    # "CANADA" and/or "USA" and some states, then they did something
    # inconsistent
    my $errstr = "";
    if (!$allused && !$countriesused && !$statesused &&
            !$provincesused)
    {
        $errstr = "No locations selected";
    }
    if ($allused &&
            ($countriesused || $statesused || $provincesused))
    {
        $errstr = "selected 'All Locations' and other locations";
    }
    if (grep(/^CA$/,@countries) && $provincesused)
    {
        $errstr = "selected 'Canada' and individual provinces";
    }
    if (grep(/^US$/,@countries) && $statesused)
    {
        $errstr = "selected 'United States' and individual states";
    }

    if ($errstr)
    {
        return ($errstr, undef, undef, undef);
    }

    if (defined($sessionId))
    {
        $sess_conn->do(
            "DELETE FROM    sess_country " .
            "WHERE          session_id = '$sessionId'");
        $sess_conn->do(
            "DELETE FROM    sess_state " .
            "WHERE          session_id = '$sessionId'");
        $sess_conn->do(
            "DELETE FROM    sess_province " .
            "WHERE          session_id = '$sessionId'");
        my $country;
        my $cntryStmt = $sess_conn->prepare(
            "INSERT " .
            "INTO           sess_country (session_id, country) " .
            "VALUES         (?, ?)");
        foreach $country (@countries)
        {
            $cntryStmt->execute($sessionId, $country);
        }
        my $state;
        my $stateStmt = $sess_conn->prepare(
            "INSERT " .
            "INTO           sess_state (session_id, state) " .
            "VALUES         (?, ?)");
        foreach $state (@states)
        {
            $state =~ s/^No State$//;
            $stateStmt->execute($sessionId, $state);
        }
        my $province;
        my $provStmt = $sess_conn->prepare(
            "INSERT " .
            "INTO           sess_province (session_id, province) " .
            "VALUES         (?, ?)");
        foreach $province (@provinces)
        {
            $province =~ s/^No Province$//;
            $provStmt->execute($sessionId, $province);
        }
        $sess_conn->commit;
    }
    return ("", \@all, \@countries, \@states, \@provinces);
}

sub putFormCSP($$$$$)
{
    my ($cg, $allref, $countryref, $stateref, $provinceref) = @_;

    print($cg->hidden('all', $allref->[0]) . "\n");
    if (scalar(@$countryref) > 0)
    {
        print($cg->hidden(-name=>'countries',
                        -default=>@$countryref) . "\n");
    }
    if (scalar(@$stateref) > 0)
    {
        print($cg->hidden(-name=>'states',
                        -default=>@$stateref) . "\n");
    }
    if (scalar(@$provinceref) > 0)
    {
        print($cg->hidden(-name=>'provinces',
                        -default=>@$provinceref) . "\n");
    }
}

sub passOnCSP($)
{
    my ($cg) = @_;

    print($cg->hidden('all', $cg->param("all")) . "\n");

    print($cg->hidden(-name=>'countries',
                    -default=>$cg->param("countries")) . "\n");

    print($cg->hidden(-name=>'states',
                    -default=>$cg->param("states")) . "\n");

    print($cg->hidden(-name=>'provinces',
                    -default=>$cg->param("provinces")) . "\n");
}

sub getCSP($)
{
    my ($cg) = @_;

    my $all = $cg->param("all");
    my @countries = $cg->param("countries");
    my @states = $cg->param("states");
    my @provinces = $cg->param("provinces");
    return ($all, \@countries, \@states, \@provinces);
}

sub formNotes($$$)
{
    my ($sessionId, $cg, $sess_conn) = @_;

    my ($note_type, $note_datasource,
        $note_navfrequency, $note_airfrequencynonmil,
        $note_airfrequencymil, $note_runways, 
        $note_tpa, $note_fixinfo) =
        (1, 1, 1, 1, 0, 1, 0, 1);

    if (defined($sessionId))
    {
        my $result = $sess_conn->prepare(
            "SELECT     note_type, note_datasource, " .
            "           note_navfrequency, note_airfrequencynonmil, " .
            "           note_airfrequencymil, note_runways, " .
            "           note_tpa, note_fixinfo " .
            "FROM       sess_main ".
            "WHERE      session_id = ?");
        $result->execute($sessionId);
        my @row = $result->fetchrow_array;
        my ($lnote_type, $lnote_datasource,
            $lnote_navfrequency, $lnote_airfrequencynonmil,
            $lnote_airfrequencymil, $lnote_runways,
            $lnote_tpa, $lnote_fixinfo) = @row;
        $note_type = $lnote_type if (defined($lnote_type));
        $note_datasource = $lnote_datasource if (defined($lnote_datasource));
        $note_navfrequency = $lnote_navfrequency
            if (defined($lnote_navfrequency));
        $note_airfrequencynonmil = $lnote_airfrequencynonmil
            if (defined($lnote_airfrequencynonmil));
        $note_airfrequencymil = $lnote_airfrequencymil
            if (defined($lnote_airfrequencymil));
        $note_runways = $lnote_runways if (defined($lnote_runways));
        $note_tpa = $lnote_tpa if (defined($lnote_tpa));
        $note_fixinfo = $lnote_fixinfo if (defined($lnote_fixinfo));
    }
    print(
        $cg->hr() . "\n" . 
        $cg->h1('Select What To Include In "Notes" For Each Waypoint') .
        "\n" .  $cg->hr() . "\n");

    print('<table border="2" width="95%"><tr><td>' . "\n");
    print($cg->checkbox(-name=>'notes',
        -value=> "type",
        -label=>"Waypoint Type",
        -checked=>($note_type)));

    print("</td><td>");

    print($cg->checkbox(-name=>'notes',
        -value=> "datasource",
        -label=>"Data Source",
        -checked=>($note_datasource)));

    print("</td><td>");

    print($cg->checkbox(-name=>'notes',
        -value=> "navfrequency",
        -label=>"Navigation Aid Frequencies",
        -checked=>($note_navfrequency)));

    print("</td></tr><tr><td>");

    print($cg->checkbox(-name=>'notes',
        -value=> "airfrequencynonmil",
        -label=>"Airport Frequencies (Non-Military)",
        -checked=>($note_airfrequencynonmil)));

    print("</td><td>");

    print($cg->checkbox(-name=>'notes',
        -value=> "airfrequencymil",
        -label=>"Airport Frequencies (Military)",
        -checked=>($note_airfrequencymil)));

    print("</td><td>");

    print($cg->checkbox(-name=>'notes',
        -value=> "runways",
        -label=>"Runways",
        -checked=>($note_runways)));

    print("</td></tr><tr><td>");

    print($cg->checkbox(-name=>'notes',
        -value=> "tpa",
        -label=>"TPA (Pattern Altitude)",
        -checked=>($note_tpa)));

    print("</td><td>");

    print($cg->checkbox(-name=>'notes',
        -value=> "fixinfo",
        -label=>"Fix definition info",
        -checked=>($note_fixinfo)));

    print("</td></tr></table>");
}

sub putNotes($$$)
{
    my ($sessionId, $sess_conn, $cg) = @_;
    my @notes = $cg->param("notes");
    if (defined($sessionId))
    {
        my $updateStr = 
            "UPDATE         sess_main " .
            "SET            note_type = ";
        if (scalar(grep(/^type$/, @notes)))
        {
            $updateStr .= 1;
        }
        else
        {
            $updateStr .= 0;
        }
        $updateStr .= ", note_datasource = ";
        if (scalar(grep(/^datasource$/, @notes)))
        {
            $updateStr .= 1;
        }
        else
        {
            $updateStr .= 0;
        }
        $updateStr .= ", note_navfrequency = ";
        if (scalar(grep(/^navfrequency$/, @notes)))
        {
            $updateStr .= 1;
        }
        else
        {
            $updateStr .= 0;
        }
        $updateStr .= ", note_airfrequencynonmil = ";
        if (scalar(grep(/^airfrequencynonmil$/, @notes)))
        {
            $updateStr .= 1;
        }
        else
        {
            $updateStr .= 0;
        }
        $updateStr .= ", note_airfrequencymil = ";
        if (scalar(grep(/^airfrequencymil$/, @notes)))
        {
            $updateStr .= 1;
        }
        else
        {
            $updateStr .= 0;
        }
        $updateStr .= ", note_runways = ";
        if (scalar(grep(/^runways$/, @notes)))
        {
            $updateStr .= 1;
        }
        else
        {
            $updateStr .= 0;
        }
        $updateStr .= ", note_tpa = ";
        if (scalar(grep(/^tpa$/, @notes)))
        {
            $updateStr .= 1;
        }
        else
        {
            $updateStr .= 0;
        }
        $updateStr .= ", note_fixinfo = ";
        if (scalar(grep(/^fixinfo$/, @notes)))
        {
            $updateStr .= 1;
        }
        else
        {
            $updateStr .= 0;
        }
        $updateStr .= 
            " WHERE          session_id = '$sessionId'";

        $sess_conn->do($updateStr);
        $sess_conn->commit;
    }
    return @notes;
}

sub putFormNotes($$)
{
    my ($cg, $notesref) = @_;
    print(
        $cg->hidden(-name=>'notes',
                    -default=>@$notesref) . "\n");
}

sub passOnNotes($)
{
    my ($cg) = @_;
    print(
        $cg->hidden(-name=>'notes',
                    -default=>$cg->param("notes")) . "\n");
}

sub getNotes($)
{
    my ($cg) = @_;
    my @notes = $cg->param("notes");
    return @notes;
}


sub formGNotes($$$)
{
    my ($sessionId, $cg, $sess_conn) = @_;

    my ($note_address, $note_type,
        $note_navfrequency, $note_datasource,
        $note_airfrequencynonmil,
        $note_airfrequencymil) =
        (undef, undef, undef, undef, undef, undef);

    if (defined($sessionId))
    {
        my $result = $sess_conn->prepare(
            "SELECT     note_address, note_type, " .
            "           note_navfrequency, " .
            "           note_datasource, " .
            "           note_airfrequencynonmil, " .
            "           note_airfrequencymil " .
            "FROM       sess_main ".
            "WHERE      session_id = ?");
        $result->execute($sessionId);
        my @row = $result->fetchrow_array;
        ($note_address, $note_type,
            $note_navfrequency, $note_datasource,
            $note_airfrequencynonmil,
            $note_airfrequencymil) = @row;
    }
    print(
        $cg->hr() . "\n" . 
        $cg->h1('Select What To Include In "Notes" For Each Waypoint') .
        "\n" .  $cg->hr() . "\n");
    print("Note that the notes field is only 160 characters long, ".
        "so it could very easily end up truncated.");

    print('<table border="2" width="95%"><tr><td>' . "\n");
    print($cg->checkbox(-name=>'notes',
        -value=> "address",
        -label=>"Address",
        -checked=>($note_address)));

    print("</td><td>");

    print($cg->checkbox(-name=>'notes',
        -value=> "type",
        -label=>"Waypoint Type",
        -checked=>($note_type)));

    print("</td><td>");

    print($cg->checkbox(-name=>'notes',
        -value=> "datasource",
        -label=>"Data Source",
        -checked=>($note_datasource)));

    print("</td></tr><tr><td>");

    print($cg->checkbox(-name=>'notes',
        -value=> "navfrequency",
        -label=>"Navigation Aid Frequencies",
        -checked=>($note_navfrequency)));

    print("</td><td>");

    print($cg->checkbox(-name=>'notes',
        -value=> "airfrequencynonmil",
        -label=>"Airport Frequencies (Non-Military)",
        -checked=>($note_airfrequencynonmil)));

    print("</td><td>");

    print($cg->checkbox(-name=>'notes',
        -value=> "airfrequencymil",
        -label=>"Airport Frequencies (Military)",
        -checked=>($note_airfrequencymil)));

    print("</td></tr></table>");
}

sub putGNotes($$$)
{
    my ($sessionId, $sess_conn, $cg) = @_;
    my @notes = $cg->param("notes");
    if (defined($sessionId))
    {
        my $updateStr = 
            "UPDATE         sess_main " .
            "SET            note_address = ";
        if (scalar(grep(/^address$/, @notes)))
        {
            $updateStr .= 1;
        }
        else
        {
            $updateStr .= 0;
        }
        $updateStr .= ", note_type = ";
        if (scalar(grep(/^type$/, @notes)))
        {
            $updateStr .= 1;
        }
        else
        {
            $updateStr .= 0;
        }
        $updateStr .= ", note_navfrequency = ";
        if (scalar(grep(/^navfrequency$/, @notes)))
        {
            $updateStr .= 1;
        }
        else
        {
            $updateStr .= 0;
        }
        $updateStr .= ", note_datasource = ";
        if (scalar(grep(/^datasource$/, @notes)))
        {
            $updateStr .= 1;
        }
        else
        {
            $updateStr .= 0;
        }
        $updateStr .= ", note_airfrequencynonmil = ";
        if (scalar(grep(/^airfrequencynonmil$/, @notes)))
        {
            $updateStr .= 1;
        }
        else
        {
            $updateStr .= 0;
        }
        $updateStr .= ", note_airfrequencymil = ";
        if (scalar(grep(/^airfrequencymil$/, @notes)))
        {
            $updateStr .= 1;
        }
        else
        {
            $updateStr .= 0;
        }
        $updateStr .= 
            "WHERE          session_id = '$sessionId'";

        $sess_conn->do($updateStr);
        $sess_conn->commit;
    }
    return @notes;
}

sub putFormGNotes($$)
{
    my ($cg, $notesref) = @_;
    print(
        $cg->hidden(-name=>'notes',
                    -default=>@$notesref) . "\n");
}

sub passOnGNotes($)
{
    my ($cg) = @_;
    print(
        $cg->hidden(-name=>'notes',
                    -default=>$cg->param("notes")) . "\n");
}

sub getGNotes($)
{
    my ($cg) = @_;
    my @notes = $cg->param("notes");
    return @notes;
}

sub formDatasources($$$$$$$)
{
    my ($sessionId, $cg, $sess_conn,
        $min_lat, $min_long, $max_lat, $max_long) = @_;

    my @sel_datasources = ();

    if (defined($sessionId))
    {
        my $result = $sess_conn->prepare(
            "SELECT     datasource " .
            "FROM       sess_datasource ".
            "WHERE      session_id = ? " .
            "ORDER BY   ds_index");
        $result->execute($sessionId);
        my @row;
        while (@row = $result->fetchrow_array)
        {
            my $ds = $row[0];
            my $ref = $datasources{$ds};
            next if ($ref->{min_long} > $max_long);
            next if ($ref->{max_long} < $min_long);
            next if ($ref->{min_lat} > $max_lat);
            next if ($ref->{max_lat} < $min_lat);
            push @sel_datasources, $ds;
        }
    }
    if (scalar(@sel_datasources) == 0)
    {
        push @sel_datasources, 1;
        push @sel_datasources, 2;
    }

    my @loc_datasources = ();
    foreach my $ds (sort {$a <=> $b} (keys(%datasources)))
    {
        my $ref = $datasources{$ds};
        next if ($ref->{min_long} > $max_long);
        next if ($ref->{max_long} < $min_long);
        next if ($ref->{min_lat} > $max_lat);
        next if ($ref->{max_lat} < $min_lat);
        push @loc_datasources, $ds;
    }

    print(
        $cg->hr() . "\n" . 
        $cg->h1('Select What Data Sources to Use, In What Order') .
        "\n" .  $cg->hr() . "\n");

    print("For a discussion on what the various data source are\n" .
            "and how much or how little to trust them,\n".
            '<a href="/datasources.html" target=other>click here</a>.' .
            "\n");

    print('<table border="2" width="95%"><tr><td>' . "\n");
    print("<tr><th>Order:</th><th>Data Source:</th></tr>\n");
    my $listlen = scalar(@loc_datasources);
    foreach my $i (1..$listlen)
    {
        print('<tr><td align="center">'.$i."</td><td>\n");
        #print('<select name="datasource_'.$i.'">'."\n");
        print('<select name="datasources">'."\n");
        print('<option value="0"');
        if ($i > scalar(@sel_datasources))
        {
            print(" selected");
        }
        print(">Nothing Selected\n");

        foreach my $ds (@loc_datasources)
        {
            my $ref = $datasources{$ds};
            print('<option value="'.$ds.'"');
            if (scalar(@sel_datasources) >= $i &&
                 $sel_datasources[$i-1] == $ds)
            {
                print(" selected");
            }
            print(">".$ref->{source_name}."\n");
        }
        print("</select></td></tr>\n");
    }
    print("</table>");
}

sub putDatasources($$$)
{
    my ($sessionId, $sess_conn, $cg) = @_;
    my @datasources = $cg->param("datasources");
    if (defined($sessionId))
    {
        my $result = $sess_conn->prepare(
            "DELETE " .
            "FROM       sess_datasource " .
            "WHERE      session_id = ?");
        $result->execute($sessionId);
        my $index = 0;
        my $dsInsertStmt = $sess_conn->prepare(
            "INSERT " .
            "INTO       sess_datasource(session_id, datasource, ds_index) " .
            "VALUES     (?, ?, ?)");
        foreach my $ds (@datasources)
        {
            next if ($ds == 0);
            $dsInsertStmt->execute($sessionId, $ds, $index);
            $index++;
        }
        $sess_conn->commit;
    }
    return @datasources;
}

sub putFormDatasources($$)
{
    my ($cg, $datasourceref) = @_;
    print(
        $cg->hidden(-name=>'datasources',
                    -default=>@$datasourceref) . "\n");
}

sub passOnDatasources($)
{
    my ($cg) = @_;
    print(
        $cg->hidden(-name=>'datasources',
                    -default=>$cg->param("datasources")) . "\n");
}

sub getDatasources($)
{
    my ($cg) = @_;
    my @datasources = $cg->param("datasources");
    return @datasources;
}

sub formTypes($$$$)
{
    my ($sessionId, $cg, $sess_conn, $useFixes) = @_;

    my @types;

    if (defined($sessionId))
    {
        my $result = $sess_conn->prepare(
                "SELECT     type " .
                "FROM       sess_type ".
                "WHERE      session_id = ?");
        $result->execute($sessionId);
        my @row;
        while (@row = $result->fetchrow_array)
        {
            push @types, $row[0];
        }
    }
    print(
        $cg->hr() . "\n" . 
        $cg->h1('Select Types of Waypoints to include') . "\n" .
        $cg->hr() . "\n");

    my $defaultTypes = scalar(@types) < 1;
    my $wpnt_type;

    my @nums  = (0, 0, 0);

    my @tabStr = (  $cg->h2('Airport Types') . "\n" .
            '<table border="2" width="95%"><tr>' . "\n",
                    $cg->h2('Navaid Types') . "\n" .
            '<table border="2" width="95%"><tr>' . "\n");
    if ($useFixes)
    {
        push (@tabStr, $cg->h2('Fix Types') . "\n" .
            '<table border="2" width="95%"><tr>' . "\n");
    }
    foreach $wpnt_type (keys(%type_categories))
    {
        my $pref = $type_categories{$wpnt_type};

        next if ($pref->{category} == Category_Intersections && !$useFixes);

        my $index = $pref->{"category"} - 1;
        my $checked = 0;
        if ($defaultTypes)
        {
            $checked = $pref->{"selected_by_default"};
        }
        else
        {
            $checked = scalar(grep(/^$wpnt_type$/, @types));
        }
        $tabStr[$index] .= "<td>" . $cg->checkbox(-name=>'types',
                                -value=>$wpnt_type,
                                -label=>" $wpnt_type",
                                -checked=>$checked) . "</td>";
        if (($nums[$index] % 3) == 2)
        {
            $tabStr[$index] .= "</tr><tr>";
        }
        $nums[$index]++;
    }
    foreach my $str (@tabStr)
    {
        print($str . "</tr></table>");
    }
}

sub putTypes($$$)
{
    my ($sessionId, $sess_conn, $cg) = @_;

    my @types = $cg->param("types");

    if (defined($sessionId))
    {
        my $result = $sess_conn->prepare(
            "DELETE FROM    sess_type " .
            "WHERE          session_id = ?");
        $result->execute($sessionId);

        my $type;
        my $insTypeStmt = $sess_conn->prepare(
                "INSERT " .
                "INTO           sess_type (session_id, type) " .
                "VALUES         (?, ?)");
        foreach $type (@types)
        {
            $insTypeStmt->execute($sessionId, $type);
        }
        $sess_conn->commit;
    }
    return @types;
}

sub putFormTypes($$)
{
    my ($cg, $typesref) = @_;
    print(
        $cg->hidden(-name=>'types',
                    -default=>@$typesref) . "\n");
}

sub passOnTypes($)
{
    my ($cg) = @_;
    print(
        $cg->hidden(-name=>'types',
                    -default=>$cg->param("types")) . "\n");
}

sub getTypes($)
{
    my ($cg) = @_;
    my @types = $cg->param("types");
    return @types;
}

sub formCharts($$$)
{
    my ($sessionId, $cg, $sess_conn) = @_;

    my $defaultCharts = -1;

    if (defined($sessionId))
    {
        my $result = $sess_conn->prepare(
                "SELECT     chart_map " .
                "FROM       sess_main ".
                "WHERE      session_id = ?");
        $result->execute($sessionId);
        my @row;
        while (@row = $result->fetchrow_array)
        {
            if (defined($row[0]))
            {
                $defaultCharts = $row[0];
            }
        }
    }
    print(
        $cg->hr() . "\n" . 
        $cg->h1('Select Waypoints on the following chart types') . "\n" .
        $cg->hr() . "\n");

    print(<<EOF);
<p>NOTE: This is highly experimental.  I'd appreciate some feedback if you
choose to use it.  Note that it's additive with the waypoint selections
above, and only applies to "Fix" types, not airports or navaids.
EOF


    print($cg->h2('Chart Types') . "\n" .
            '<table border="2" width="95%"><tr>' . "\n");

    my $nums = 0;

    foreach my $chart (keys(%map_categories))
    {
        my $pref = $map_categories{$chart};

        my $longname = $pref->{"longname"};

        my $checked = 0;
        if ($defaultCharts > 0)
        {
            $checked = ($pref->{"type"} & $defaultCharts) != 0;
        }
        else
        {
            $checked = $pref->{"selected_by_default"};
        }
        print("<td>" . $cg->checkbox(-name=>'charts',
                                -value=>$chart,
                                -label=>" $longname",
                                -checked=>$checked) . "</td>");
        if (($nums % 3) == 2)
        {
            print("</tr><tr>");
        }
        $nums++;
    }
    print("</tr></table>");
}

sub putCharts($$$)
{
    my ($sessionId, $sess_conn, $cg) = @_;
    my @charts = $cg->param("charts");
    my $chart_map = 0;
    foreach (@charts)
    {
        $chart_map |= $_;
    }

    if (defined($sessionId))
    {
        my $type;
        my $updateStr = $sess_conn->prepare(
            "UPDATE         sess_main " .
            "SET            chart_map = ? " .
            "WHERE          session_id = ?");
        $updateStr->execute($chart_map, $sessionId);
        $sess_conn->commit;

    }
    return $chart_map;
}

sub putFormCharts($$)
{
    my ($cg, $chart_map) = @_;
    print(
        $cg->hidden(-name=>'chart_map',
                    -default=>$chart_map) . "\n");
}

sub passOnCharts($)
{
    my ($cg) = @_;
    print(
        $cg->hidden(-name=>'chart_map',
                    -default=>$cg->param("chart_map")) . "\n");
}

sub getCharts($)
{
    my ($cg) = @_;
    my $chart_map = $cg->param("chart_map");
    return $chart_map;
}

sub formDetails($$$$)
{
    my ($sessionId, $cg, $sess_conn, $doMetric) = @_;

    my ($isPublic, $isPrivate, $expandCountry, $isMetric, $runwaylen) =
        (1, 1, 0, 0, 0);

    if (defined($sessionId))
    {
        my $result = $sess_conn->prepare(
            "SELECT     isprivate, expandcountry, ismetric, " .
            "           min_runway_length " .
            "FROM       sess_main ".
            "WHERE      session_id = ?");
        $result->execute($sessionId);
        my @row = $result->fetchrow_array;
        ($isPrivate, $expandCountry, $isMetric, $runwaylen) = @row;
    }

    print($cg->h2('Fine Details') . "\n");
    print(<<EOF);
<table border="2" width="95%">
<tr>
<td>Include Public Airports/Navaids?</td>
<td><input type="radio" name="ispublic" value="yes" checked>Yes</td>
<td><input type="radio" name="ispublic" value="no">No</td>
</tr><tr>
<td>Include Private Airports/Navaids?</td>
EOF
    print(
        '<td><input type="radio" name="isprivate" value="yes"' .
        (($isPrivate)?" checked":"") . ">Yes</td>\n");
    print(
        '<td><input type="radio" name="isprivate" value="no"' .
        ((!$isPrivate)?" checked":"") . ">No</td>\n");
    print(<<EOF);
</tr><tr>
<td>Expand Country Codes?</td>
EOF
    print(
        '<td><input type="radio" name="expandCountry" value="yes"' .
        (($expandCountry)?" checked":"") . ">Yes</td>\n");
    print(
        '<td><input type="radio" name="expandCountry" value="no"' .
        ((!$expandCountry)?" checked":"") . ">No</td>\n");

    print(<<EOF);
</tr><tr>
<td>Minimum Airport Runway Length: <input type="text" name="runwaylen"
value="$runwaylen"></td>
EOF
	  print(
		  '<td><input type="radio" name="isMetric" value="no"' .
		  ((!$isMetric)?" checked":"") . ">Feet</td>\n");
	  print(
		  '<td><input type="radio" name="isMetric" value="yes"' .
		  (($isMetric)?" checked":"") . ">Metres</td>\n");

	if ($doMetric)
	{
	  print(<<EOF);
</tr><tr>
<td>Even if you leave the runway length as 0 above, the "Feet" or "Metres"
checkbox will still control whether runway lengths and widths are put in
the notes in feet or metres.
EOF
    }

    print("</td></tr></table>");
}

sub putDetails($$$)
{
    my ($sessionId, $sess_conn, $cg) = @_;
    my $isPublic = ($cg->param("ispublic") eq "yes")?1:0;
    my $isPrivate = ($cg->param("isprivate") eq "yes")?1:0;
    my $expandCountry = ($cg->param("expandCountry") eq "yes")?1:0;
    my $isMetric = ($cg->param("isMetric") eq "yes")?1:0;
    my $runwaylen = $cg->param("runwaylen");

    if (defined($sessionId))
    {
        my $updateStr = $sess_conn->prepare(
            "UPDATE         sess_main " .
            "SET            isprivate = ?, " .
            "               expandcountry = ?, ".
            "               ismetric = ?, ".
            "               min_runway_length = ? ".
            "WHERE          session_id = ?");
        $updateStr->execute($isPrivate, $expandCountry, $isMetric,
                $runwaylen, $sessionId);
        $sess_conn->commit;
    }
    return ($isPublic, $isPrivate, $expandCountry, $isMetric, $runwaylen);
}

sub putFormDetails($$$$$$)
{
    my ($cg, $isPublic, $isPrivate, $expandCountry, $isMetric, $runwaylen) = @_;
    print(
        $cg->hidden(-name=>'ispublic',
                    -default=>$isPublic) . "\n");
    print(
        $cg->hidden(-name=>'isprivate',
                    -default=>$isPrivate) . "\n");
    print(
        $cg->hidden(-name=>'expandCountry',
                    -default=>$expandCountry) . "\n");
    print(
        $cg->hidden(-name=>'isMetric',
                    -default=>$isMetric) . "\n");
    print(
        $cg->hidden(-name=>'runwaylen',
                    -default=>$runwaylen) . "\n");
}

sub passOnDetails($)
{
    my ($cg) = @_;
    print(
        $cg->hidden(-name=>'ispublic',
                    -default=>$cg->param("ispublic")) . "\n");
    print(
        $cg->hidden(-name=>'isprivate',
                    -default=>$cg->param("isprivate")) . "\n");
    print(
        $cg->hidden(-name=>'expandCountry',
                    -default=>$cg->param("expandCountry")) . "\n");

    print(
        $cg->hidden(-name=>'isMetric',
                    -default=>$cg->param("isMetric")) . "\n");

    print(
        $cg->hidden(-name=>'runwaylen',
                    -default=>$cg->param("runwaylen")) . "\n");
}

sub getDetails($)
{
    my ($cg) = @_;
    my $isPublic = $cg->param("ispublic");
    my $isPrivate = $cg->param("isprivate");
    my $expandCountry = $cg->param("expandCountry");
    my $isMetric = $cg->param("isMetric");
    my $runwaylen = $cg->param("runwaylen");
    return ($isPublic, $isPrivate, $expandCountry, $isMetric, $runwaylen);
}

sub startGeneratorProcess($$$$$$$$$$$$$$$$$$$$$)
{
    my ($pgm, $outfiletype, $outfilename, $logname,
        $all, $countryref, $stateref, $provinceref, $typesref,
        $datasourcesref, $notesref,
        $max_lat, $min_lat, $max_long, $min_long,
        $public, $private, $expandCountry, $isMetric, $runwaylen,
        $otherref) = @_;

    my $tmpdir = "/www/navaid.com/tmp/";
    #open(DEBUG,">>${tmpdir}library.out");
    #my $ofh = select(DEBUG); $| = 1; select $ofh;

    my @execargs = ($outfiletype, $outfilename, "-logname", $logname);

    push(@execargs, @$otherref);

    if (!$all)
    {
        if (scalar(@$countryref) > 0)
        {
            foreach my $cs (@$countryref)
            {
                push(@execargs, "-country", $cs);
            }
        }
        if (scalar(@$stateref) > 0)
        {
            foreach my $ss (@$stateref)
            {
                push(@execargs, "-state", $ss);
            }
        }
        if (scalar(@$provinceref) > 0)
        {
            foreach my $ps (@$provinceref)
            {
                push(@execargs, "-province", $ps);
            }
        }
    }
    if (scalar(@$typesref) > 0)
    {
        foreach my $ts (@$typesref)
        {
            push(@execargs, "-type", $ts);
        }
    }
    if (scalar(@$datasourcesref) > 0)
    {
        foreach my $ds (@$datasourcesref)
        {
            next if ($ds == 0);
            push(@execargs, "-datasource", $ds);
        }
    }
    if (scalar(@$notesref) > 0)
    {
        foreach my $ns (@$notesref)
        {
            push(@execargs, "-note", $ns);
        }
    }
    push(@execargs, "-max_lat", $max_lat, "-min_lat", $min_lat);
    push(@execargs, "-max_long", $max_long, "-min_long", $min_long);

    if (!$public)
    {
        push(@execargs, "-nopublic");
    }
    if (!$private)
    {
        push(@execargs, "-noprivate");
    }

    if ($expandCountry)
    {
        push(@execargs, "-expandCountry");
    }
    else
    {
        push(@execargs, "-noexpandCountry");
    }

    if ($isMetric)
    {
        push(@execargs, "-metric");
    }
    else
    {
        push(@execargs, "-nometric");
    }

    if ($runwaylen > 0)
    {
        push(@execargs, "-runway", $runwaylen);
    }

    $SIG{CHLD} = 'IGNORE';

    # This should flush stdout.
    my $ofh = select(STDOUT);$| = 1;select $ofh;

    my $kpid = fork;
    #print DEBUG "kpid = $kpid\n";
    if ($kpid)
    {
        # Parent process
        waitpid($kpid, 0);
        #print DEBUG "$kpid has finished\n";
        #close(DEBUG);
    }
    else
    {
        #print DEBUG "in child\n";
        close STDIN;
        close STDOUT;
        close STDERR;
        setsid();
        #print DEBUG "after setsid\n";
        my $gpid = fork;
        #print DEBUG "gpid = $gpid\n";
        if (!$gpid)
        {
            #open(DEBUG2,">>${tmpdir}library2.out");
            #my $ofh = select(DEBUG2);$| = 1;select $ofh;
            #print DEBUG2 "starting grandchild\n";
            #open(STDOUT, ">/home/ptomblin/tmp/stdout");
            #open(STDERR, ">/home/ptomblin/tmp/stderr");
            open(STDIN, "</dev/null") ;#or print DEBUG2 "can't redirect stdin\n";
            open(STDOUT, ">/dev/null") ;#or print DEBUG2 "can't redirect stdout\n";
            open(STDERR, ">/dev/null") ;#or print DEBUG2 "can't redirect stderr\n";
            #print DEBUG2 "execing $pgm\n";
            # Child process
            exec($pgm, @execargs) ;# or print DEBUG2 "exec failed\n";
        }
        exit 0;
    }
}

sub startGeneratorProcess2($$$$$$$$$$$$$$$$$$$$$)
{
    my ($pgm, $outfiletype, $outfilename, $logname,
        $all, $countryref, $stateref, $provinceref, $typesref,
        $datasourcesref, $notesref,
        $max_lat, $min_lat, $max_long, $min_long,
        $public, $private, $expandCountry, $isMetric, $runwaylen,
        $otherref) = @_;

    my $tmpdir = "/www/navaid.com/tmp/";
    open(DEBUG,">>${tmpdir}library.out");
    my $ofh = select(DEBUG); $| = 1; select $ofh;

    my @execargs = ($pgm, $outfiletype, $outfilename, "-logname", $logname);

    push(@execargs, @$otherref);

    if (!$all)
    {
        if (scalar(@$countryref) > 0)
        {
            foreach my $cs (@$countryref)
            {
                push(@execargs, "-country", $cs);
            }
        }
        if (scalar(@$stateref) > 0)
        {
            foreach my $ss (@$stateref)
            {
                push(@execargs, "-state", $ss);
            }
        }
        if (scalar(@$provinceref) > 0)
        {
            foreach my $ps (@$provinceref)
            {
                push(@execargs, "-province", $ps);
            }
        }
    }
    if (scalar(@$typesref) > 0)
    {
        foreach my $ts (@$typesref)
        {
            push(@execargs, "-type", $ts);
        }
    }
    if (scalar(@$datasourcesref) > 0)
    {
        foreach my $ds (@$datasourcesref)
        {
            next if ($ds == 0);
            push(@execargs, "-datasource", $ds);
        }
    }
    if (scalar(@$notesref) > 0)
    {
        foreach my $ns (@$notesref)
        {
            push(@execargs, "-note", $ns);
        }
    }
    push(@execargs, "-max_lat", $max_lat, "-min_lat", $min_lat);
    push(@execargs, "-max_long", $max_long, "-min_long", $min_long);

    if (!$public)
    {
        push(@execargs, "-nopublic");
    }
    if (!$private)
    {
        push(@execargs, "-noprivate");
    }

    if ($expandCountry)
    {
        push(@execargs, "-expandCountry");
    }
    else
    {
        push(@execargs, "-noexpandCountry");
    }

    if ($isMetric)
    {
        push(@execargs, "-metric");
    }
    else
    {
        push(@execargs, "-nometric");
    }

    if ($runwaylen ne "" && $runwaylen > 0)
    {
        push(@execargs, "-runway", $runwaylen);
    }
    print DEBUG "execargs = ", join(" ", @execargs), "\n";
    close DEBUG;
    system("/www/navaid.com/bin/respawn_something", @execargs);
}

1;
__END__

