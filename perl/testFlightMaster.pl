#!/usr/bin/perl -w
use strict;
use CoPilot::FlightMaster;
use BoundaryConstants;
use Datasources;
use Data::Dumper;

my $pdb = new CoPilot::FlightMaster;

#my $lat = 80.6;
#my $lon = 80.2;
#my $ilat = CoPilot::FlightMaster::deg2Int32($lat);
#my $ilon = CoPilot::FlightMaster::deg2Int32($lon);
#print "ilat, ilon = $ilat, $ilon\n";
#my $clat = CoPilot::FlightMaster::latcell($ilat);
#my $clon = CoPilot::FlightMaster::longcell($ilon);
#print "cell = ", $clat+$clon, "\n";

my $record = $pdb->create_Record("AAA", BoundaryConstants::BDRY_TYPE_TCA, 'C',
    45.0, 30.0, 75.0, 40.2,
    'KROC',
    0, BoundaryConstants::ALT_TYPE_AGL,
    4000, BoundaryConstants::ALT_TYPE_MSL,
    Datasources::DATASOURCE_DAFIF, 118.75, "Test Area");
$pdb->add_Line($record, 45.5, 22.2, 46.5, 23.2);    
$pdb->add_Line($record, 46.5, 23.2, 45.2, 22.0);    
$pdb->add_Line($record, 45.2, 22.0, 50.1, -18.0);    

$record = $pdb->create_Record("BBB", BoundaryConstants::BDRY_TYPE_WARNING, undef,
    -55.0, -12.0, 11.0, -11,
    'KART',
    4000, BoundaryConstants::ALT_TYPE_MSL,
    240, BoundaryConstants::ALT_TYPE_FLIGHT_LEVEL,
    Datasources::DATASOURCE_DAFIF, 118.75, "Test Area");
$pdb->add_Line($record, -89, -179, 89, 179);    

print Dumper($pdb);

