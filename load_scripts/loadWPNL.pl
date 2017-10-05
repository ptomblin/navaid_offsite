#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use Datasources;
use WPInfo;

use DBLoad;
my $wp_db_name = WPInfo::getLoadDB();
DBLoad::initialize($wp_db_name);

my %NL_country_codes =
  ("België" => "BE", "Bulgarije" => "BU", "Cyprus" => "CY",
  "Denenmarken" => "DA", "Duitsland" => "GM", "Engeland" => "UK",
    "Finland" => "FI", "Frankrijk" => "FR", "Griekenland" => "GR",
	"Hongarije" => "HU", "Ierland" => "EI", "Italië" => "IT",
	"Kroatië" => "HR", "Luxemburg" => "LU", "Malta" => "MT",
	"Nederland" => "NL", "Noorwegen" => "NO", "Oostenrijk" => "AU",
	"Polen" => "PL", "Portugal" => "PO", "Roemenië" => "RO",
	"Slovakije" => "LO", "Slovenië" => "SI", "Spanje" => "SP",
	"Tjechië" => "EZ", "Turkije" => "TU", "Zweden" => "SW",
	"Zwitserland" => "SZ");

sub parseLatLong($)
{
	my $latLong = shift;

	my $mult = 1.0;

	my ($deg, $min, $dec) = split('\.', $latLong);

	if (substr($deg, 0, 1) eq "W")
	{
		$mult = -1.0;
		$deg = substr($deg, 1);
	}

	my $degrees = $deg + ($min/60.0) + ($dec/60000.0);

	return $degrees * $mult;
}

sub NLToICAOCountry($)
{
	my $country = shift;

	if (exists($NL_country_codes{$country}))
	{
		$country = $NL_country_codes{$country};
	}
	else
	{
		die "Missing country: $country\n";
	}

	return $country;
}

sub delete_NL_data()
{
	deleteWaypointData(Datasources::DATASOURCE_WPNL);

}

sub parseNLWaypointAirportRecord($)
{
	my ($line) = @_;
	$line =~ s/  *\t/\t/g;	# get rid of trialing blanks.

	my ($name, $country, $northing, $easting, $id, $type) =
			split("\t", $line);

	#$name =~ s/'/''/g;
	$country = NLToICAOCountry($country);

	my $isPublic = 1;

	my $lat = parseLatLong($northing);

	my $long = -parseLatLong($easting);

	my $datasource_key = "NL_$id";

	my $decl = getMagVar($lat, $long, 0);

	insertWaypoint($id, $datasource_key, "AIRPORT", $name, "",
					"", $country, $lat, $long, $decl, 0,
					"", Datasources::DATASOURCE_WPNL, $isPublic, 0);

	return $datasource_key;
}

sub read_NL_Airports($)
{
    my ($fn) = @_;

    my $fh = new IO::File($fn) or die "Airport file not found";

	<$fh>;
    while (<$fh>)
    {
        chomp;
		parseNLWaypointAirportRecord($_);
	}
    undef $fh;
}

my $NLfn = shift;

delete_NL_data();
print "NL data is deleted\n";

print "loading NL airports\n";
read_NL_Airports($NLfn);

updateDatasourceExtents(Datasources::DATASOURCE_WPNL);

finish();
print "Done\n";

