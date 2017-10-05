#!/usr/bin/perl -w

use DBI;

use strict;

#use Datasources;

use WPInfo;
#use WaypointDB;

use constant INDEXSTR =>
		" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

sub encodeId($)
{
	my $id = shift;
	my $pdb_id = 0;
	my $len = length($id);

	if ($len <= 4)
	{
		my $index;
		for ($index = 0; $index < $len; $index++)
		{
			my $char = substr($id, $index, 1);
			my $ord = index(INDEXSTR, $char);
			$pdb_id = ($pdb_id << 6) + $ord;
		}
	}
	return $pdb_id;
}

sub decodeId($)
{
	my $pdb_id = shift;
	my $retStr = "";
	while ($pdb_id > 0)
	{
		my $lower6 = $pdb_id & 63;
		my $char = substr(INDEXSTR, $lower6, 1);
		$retStr = $char . $retStr;
		$pdb_id = $pdb_id >> 6;
	}
	return $retStr;
}

my $wp_db_name = WPInfo::getLoadDB();

my $wp_conn;
$wp_conn = DBI->connect(
	"DBI:mysql:database=$wp_db_name;host=mysqldb.gradwell.net",
	"waypoints", "2nafish") or die $wp_conn->errstr;

my $maxNumber = 1;
my $foundNumber = 0;
my @row;

my $getMaxStmt = $wp_conn->prepare(
	"SELECT		pdb_id " .
	"FROM		id_mapping " .
	"WHERE		id = 'MAXNUMBER'");
$getMaxStmt->execute() or die $getMaxStmt->errstr;
while (@row = $getMaxStmt->fetchrow_array)
{
	$maxNumber = shift(@row);
	$foundNumber = 1;
}
print "before fetching long ids, maxNumber = $maxNumber\n";

my $selectLongStmt = $wp_conn->prepare(
	"SELECT		id " .
	"FROM		id_mapping " .
	"WHERE		pdb_id is null and length(id) > 4");

my $selectShortStmt = $wp_conn->prepare(
	"SELECT		id " .
	"FROM		id_mapping " .
	"WHERE		pdb_id is null and length(id) < 5");

my $isTaken = $wp_conn->prepare(
	"SELECT		1 " .
	"FROM		id_mapping " .
	"WHERE		pdb_id = ? and id != 'MAXNUMBER'");

my $updateIdStmt = $wp_conn->prepare(
	"UPDATE		id_mapping " .
	"SET		pdb_id = ? " .
	"WHERE		id = ?");

my $updatePdbStmt = $wp_conn->prepare(
	"UPDATE		id_mapping " .
	"SET		pdb_id = ? " .
	"WHERE		pdb_id = ?");

$selectLongStmt->execute() or die $selectLongStmt->errstr;

# Insert numbers in the ones that aren't encodable
while (@row = $selectLongStmt->fetchrow_array)
{
	my ($id) = @row;

print "mapping $id to $maxNumber\n";
	$updateIdStmt->execute($maxNumber++, $id);
}

if ($foundNumber)
{
	$updateIdStmt->execute($maxNumber, "MAXNUMBER");
}
else
{
	$wp_conn->do(	"INSERT INTO id_mapping(id, pdb_id) " .
					"VALUES	('MAXNUMBER', " . $maxNumber . ")");
}
print "After long ids, maxNumber = $maxNumber\n";

$selectShortStmt->execute() or die $selectShortStmt->errstr;

# Now do the encodable, fixing any that encode into existing numbers.
while (@row = $selectShortStmt->fetchrow_array)
{
	my ($id) = @row;
	my $pdb_id = encodeId($id);

	if ($pdb_id < $maxNumber)
	{
		# This one overlaps one that's already assigned, so reassign it.
		my $notFound = 1;
		while ($notFound)
		{
			$isTaken->execute($maxNumber);
			if (@row = $isTaken->fetchrow_array)
			{
print "trying to remap $pdb_id to $maxNumber, already taken\n";
				$maxNumber++;
			}
			else
			{
				$notFound = 0;
			}
		}
print "remapping $pdb_id to $maxNumber\n";

		$updatePdbStmt->execute($maxNumber++, $pdb_id);
	}

print "mapping $id to $pdb_id\n";
	$updateIdStmt->execute($pdb_id, $id);
}

$updateIdStmt->execute($maxNumber, "MAXNUMBER");


$wp_conn->disconnect;

