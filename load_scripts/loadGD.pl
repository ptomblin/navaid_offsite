#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use Datasources;
use WPInfo;

use DBLoad;
my $wp_db_name = WPInfo::getLoadDB();
DBLoad::initialize($wp_db_name);

sub delete_GD_data()
{
	deleteWaypointData(Datasources::DATASOURCE_FR_GD);
}

sub parseRunway($$)
{
	my ($rwy, $len) = @_;
	print "...rwy = [$rwy], len = [$len]\n";
}

sub read_GD($)
{
    my $fn = shift;

    my $fh = new IO::File($fn) or die "Airport file $fn not found";

	<$fh>;
    while (<$fh>)
    {
        chomp;
		s/  *\t/\t/;
		# Since "uc" doesn't seem to handle accented characters, do it
		# here.
		tr/ÈËÍ‚ÙÓ˚ÁÎ/…» ¬‘Œ€«À/;
		my $line = uc;

		my ($name, $id, $type, $freq, $latitude, $longitude, $altitude,
			 $qfu, $rwy1, $rwy2, $rwy3, $len1, $len2, $len3) =
				split("\t", $line);
		my $isPublic = 1;
		if ($type eq "ULM")
		{
			$type = 'ULTRALIGHT';
		} elsif ($type eq "PRIV…")
		{
			$type = 'AIRPORT';
			$isPublic = 0;
		} elsif ($type eq "A…RODROME")
		{
			$type = 'AIRPORT';
		}
		else
		{
			print "INVALID TYPE $type\n";
			next;
		}

		my $decl = getMagVar($latitude, $longitude, $altitude);

		my $datasource_key = "GD_APT_$id";

		if ($freq eq "0")
		{
			$freq = "";
		}

		insertWaypoint($id, $datasource_key, $type, $name, "",
						"", "FR", $latitude, $longitude, $decl,
						$altitude, $freq,
						Datasources::DATASOURCE_FR_GD,
						$isPublic, 0);

		parseRunway($rwy1, $len1);
		parseRunway($rwy2, $len2);
		parseRunway($rwy3, $len3);
	}
    undef $fh;
}

my $FRapt = shift;

delete_GD_data();
print "GD data is deleted\n";

print "loading GD airports\n";
read_GD($FRapt);

updateDatasourceExtents(Datasources::DATASOURCE_FR_GD);

finish();
print "Done\n";

