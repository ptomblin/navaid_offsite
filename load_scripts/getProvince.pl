#!/usr/bin/perl -w

use strict;

use DBI;
use Time::HiRes qw(tv_interval gettimeofday usleep);

use LWP;

use XML::Simple;

use Data::Dumper;

my $ua = LWP::UserAgent->new;

my %provinceLookup = 
(
  "Alberta" => "AB",
  "British Columbia" =>  "BC",
  "Manitoba" =>  "MB",
  "New Brunswick" =>  "NB",
  "Newfoundland" =>  "NF",
  "Newfoundland and Labrador" =>  "NF",
  "Northwest Territories" =>  "NT",
  "Nova Scotia" =>  "NS",
  "Nunavut" =>  "NU",
  "Ontario" =>  "ON",
  "Prince Edward Island" =>  "PE",
  "Quebec" =>  "QC",
  "Saskatchewan" =>  "SK",
  "Yukon Territory" =>  "YT"
);

my $conn;
$conn = DBI->connect(
        "DBI:mysql:database=navaid",
        "ptomblin", "navaid") or die $conn->errstr;
$conn->{"AutoCommit"} = 0;

my $simple = XML::Simple->new;

my $updateProvStmt = $conn->prepare(
		"UPDATE		waypoint " .
		"SET		state = ? " .
		"WHERE		datasource_key = ?");

my $getWptStmt = $conn->prepare(
		"SELECT		id, datasource_key, latitude, longitude, state " .
		"FROM		waypoint " .
		"WHERE		country = 'CA' AND datasource = 99 " .
		"			AND orig_datasource != 24"
		);

$getWptStmt->execute()
or die $conn->errstr;

my %wpt;

while (my @row = $getWptStmt->fetchrow_array)
{
  my ($id, $ds_key, $lat, $lon, $prov) = @row;
  $wpt{$id} = { "id" => $id,
  				"ds_key" => $ds_key,
  				"lat" => $lat,
				"lon" => $lon,
				"prov" => $prov
			 };

}

sub changeProvince($$)
{
  my ($wpt, $province) = @_;

  print "changing ", $wpt->{id}, "'s (", $wpt->{ds_key},
		") province from ",
  		$wpt->{prov}, " to [", $province, "]\n";
  $updateProvStmt->execute($province, $wpt->{ds_key})
  or die $updateProvStmt->errstr;
}

sub checkProv($$)
{
  my ($wpt, $subDivision) = @_;

#print "checkProv: ", Dumper($wpt), "\n", Dumper($subDivision), "\n";
  if ($subDivision->{countryCode} ne "CA")
  {
	print "ignoring non-Canada results", Dumper($subDivision), "\n";
	return;
  }

  if (defined($subDivision->{adminName1}))
  {
	  if (defined($provinceLookup{$subDivision->{adminName1}}))
	  {
		my $province = $provinceLookup{$subDivision->{adminName1}};
		if ($province ne $wpt->{prov})
		{
		  changeProvince($wpt, $province);
		}
		else
		{
		  print ".";
		}
	  }
	  else
	  {
		print $wpt->{id}, ": can't do NU or NWT\n";
	  }
  }
  else
  {
	print "invalid subDivision: ", Dumper($subDivision), "\n";
  }
}

foreach my $id (keys(%wpt))
{
  my $lat = $wpt{$id}->{lat};
  my $lon = $wpt{$id}->{lon};
  $lon = -1.0 * $lon;


  my $req = HTTP::Request->new(
	  GET =>
	  "http://ws.geonames.org/countrySubdivision?lat=$lat&lng=$lon");

  my $res = $ua->request($req);

  if ($res->is_success)
  {
	my $simpled = $simple->XMLin($res->content);
#print Dumper($simpled), "\n";
	if (defined($simpled->{countrySubdivision}))
	{
	  my $hashRef = $simpled->{countrySubdivision};
	  if (ref($hashRef) eq "HASH")
	  {
		checkProv($wpt{$id}, $hashRef);
	  }
	  else
	  {
		foreach my $subDvisions (@${hashRef})
		{
		  checkProv($wpt{$id}, $subDvisions);
		}
	  }
	}
	else
	{
	  if (defined($simpled->{status}) &&
		defined($simpled->{status}->{value}) &&
		$simpled->{status}->{value} == 15)
	  {
		# point is outside any province
		if ($wpt{$id}->{prov} ne "")
		{
		  changeProvince($wpt{$id}, "");
		}
		else
		{
		  print ".";
		}
	  }
	  else
	  {
		print "can't change province for $id from ", $wpt{$id}->{prov}, "\n";
		print "can't parse: ", Dumper($simpled), "\n";
	  }
	}
  }
  else
  {
	print $res->status_line, "\n";
  }
  usleep(100);
}

print "committing!\n";
$conn->commit
or die $conn->errstr;
$conn->disconnect
or die $conn->errstr;
