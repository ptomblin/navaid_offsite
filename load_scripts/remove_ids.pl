#!/usr/bin/perl -w

use DBI;

use strict;

use WPInfo;

my $wp_db_name = WPInfo::getLoadDB();

my $wp_conn;
$wp_conn = DBI->connect(
	"DBI:mysql:database=navaid;",
	"navaid", "2nafish2") or die $wp_conn->errstr;

# Prepare a statement to see if the id exists in the database
my $idStmt = $wp_conn->prepare(
    "SELECT     1 " .
    "FROM       waypoint " .
    "WHERE      id = ?");
# Prepare a statement to remove the id from id_mapping
my $rmStmt = $wp_conn->prepare(
    "DELETE " .
    "FROM       id_mapping " .
    "WHERE      id = ?");

my $maxNumber = 9999999;

# Get all the ids in id_mapping
my $idRef = $wp_conn->selectall_arrayref(
	"SELECT		id, pdb_id " .
	"FROM		id_mapping " .
	"WHERE		id != 'MAXNUMBER'");
foreach my $rowRef (@{$idRef})
{
    my $id = $rowRef->[0];
    my $pdb_id = $rowRef->[1];
    # See if there is an id for this one
    my $existsRef = $wp_conn->selectrow_arrayref($idStmt, undef, ($id));
    my $exists = defined($existsRef) && scalar(@{$existsRef}) > 0;
    print "id = $id - exists = $exists\n";
    if (!$exists)
    {
        $rmStmt->execute(($id));
        if ($pdb_id < $maxNumber)
        {
            $maxNumber = $pdb_id;
        }
    }
}

$wp_conn->do(
    "UPDATE     id_mapping " .
    "SET        pdb_id = $maxNumber " .
    "WHERE      id = 'MAXNUMBER'"); 

$wp_conn->disconnect;

