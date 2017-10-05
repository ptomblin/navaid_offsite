#!/usr/bin/perl -w
#File DBUtils.pm
#
#	subs to retrieve and save waypoints.
#
#   This file is copyright (c) 2001 by Paul Tomblin, and may be distributed
#   under the terms of the "Clarified Artistic License", which should be
#   bundled with this file.  If you receive this file without the Clarified
#   Artistic License, email ptomblin@xcski.com and I will mail you a copy.
#

BEGIN
{
    push @INC, "/www/navaid.com/perl";
}

use strict;

use  DBUtils;
use Data::Dumper;

print "getting record\n";
my $record = getWaypoint("NL_EIK");

print "original record: ", Dumper($record);

my $newRecord = clone($record);

print "clone record: ", Dumper($newRecord);

my $nearMatchArr = getNearMatch(99, $record->{datasource}, $record->{id},
    $record->{country}, $record->{state}, $record->{type},
    $record->{latitude}, $record->{longitude});

print "near matches = ", Dumper($nearMatchArr);

foreach my $rec (@$nearMatchArr)
{
    my $newRecord = clone($record);
    my $diffs = compareWaypoints($rec, $newRecord);
    print "$diffs differences.  Result = ", Dumper($newRecord);
}

commitAndClose();
