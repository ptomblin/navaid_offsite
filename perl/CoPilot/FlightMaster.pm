# CoPilot::FlightMaster.pm
#
# Perl class for dealing with CoPilot FlightMaster databases
#
#	Copyright (C) 2005, Paul Tomblin
#	You may distribute this file under the terms of the Clarified Artistic
#	License, as specified in the LICENSE file.
#
# $Id$

use strict;
package CoPilot::FlightMaster;
use Palm::Raw();
use Math::Trig;
use BoundaryConstants;
use Data::Dumper;
use vars qw( $VERSION @ISA );

$VERSION = (qw( $Revision: 1.13 $ ))[1];
@ISA = qw( Palm::Raw );

# Type constants
use constant asTypeClassA       =>  0x0010;
use constant asTypeClassBG      =>  0x0020;
use constant asTypeSUAS         =>  0x0040;
use constant asTypeLowAirway    =>  0x0080;
use constant asTypeHighAirway   =>  0x0100;
use constant asTypeOther        =>  0x8000;
use constant asTypeAirspace     =>  (asTypeClassA | asTypeClassBG | asTypeSUAS);
use constant asTypeAirway       =>  (asTypeLowAirway | asTypeHighAirway);

use constant asTypeMask         =>  0xFFF0;
use constant asSubTypeMask      =>  0x000F;

# Subtype constants
use constant asClassA           =>  0x0000;
use constant asClassB           =>  0x0001;
use constant asClassC           =>  0x0002;
use constant asClassD           =>  0x0003;
use constant asClassE           =>  0x0004;
use constant asClassF           =>  0x0005;
use constant asClassG           =>  0x0006;

use constant suasAlert          =>  0x0000;
use constant suasDanger         =>  0x0001;
use constant suasMoa            =>  0x0002;
use constant suasProhibited     =>  0x0003;
use constant suasRestricted     =>  0x0004;
use constant suasTra            =>  0x0005;
use constant suasWarning        =>  0x0006;

my %typeTranslations = 
(
BoundaryConstants::BDRY_TYPE_ADVISORY_AREA      =>  asTypeSUAS,
BoundaryConstants::BDRY_TYPE_ADIZ               =>  asTypeSUAS,
BoundaryConstants::BDRY_TYPE_ARTCC              =>  asTypeSUAS,
BoundaryConstants::BDRY_TYPE_AREA_CONTROL_CENTER=>  asTypeSUAS,
BoundaryConstants::BDRY_TYPE_BUFFER_ZONE        =>  asTypeSUAS,
BoundaryConstants::BDRY_TYPE_CONTROL_AREA       =>  asTypeSUAS,
BoundaryConstants::BDRY_TYPE_CONTROL_ZONE       =>  asTypeSUAS,
BoundaryConstants::BDRY_TYPE_FIR                =>  asTypeSUAS,
BoundaryConstants::BDRY_TYPE_OCEAN_CONTROL_AREA =>  asTypeSUAS,
BoundaryConstants::BDRY_TYPE_RADAR_AREA         =>  asTypeSUAS,
BoundaryConstants::BDRY_TYPE_TCA                =>  asTypeSUAS,
BoundaryConstants::BDRY_TYPE_UPPER_FLIGHT_INFO  =>  asTypeSUAS,
BoundaryConstants::BDRY_TYPE_MODE_C_DEFINED     =>  asTypeSUAS,
BoundaryConstants::BDRY_TYPE_OTHER              =>  asTypeSUAS,
BoundaryConstants::BDRY_TYPE_ALERT              =>  asTypeSUAS|suasAlert,
BoundaryConstants::BDRY_TYPE_DANGER             =>  asTypeSUAS|suasDanger,
BoundaryConstants::BDRY_TYPE_MOA                =>  asTypeSUAS|suasMoa,
BoundaryConstants::BDRY_TYPE_PROHIBITED         =>  asTypeSUAS|suasProhibited,
BoundaryConstants::BDRY_TYPE_RESTRICTED         =>  asTypeSUAS|suasRestricted,
BoundaryConstants::BDRY_TYPE_TEMPORARY          =>  asTypeSUAS|suasTra,
BoundaryConstants::BDRY_TYPE_WARNING            =>  asTypeSUAS|suasWarning,
);

use constant altAmsl                            => 0;
use constant altAgl                             => 1;
use constant altFL                              => 2;
use constant altNotam                           => 3;

use constant segLine                            => 'l';
use constant segArc                             => 'a';

my %altTranslations =
(
    BoundaryConstants::ALT_TYPE_AGL             =>  altAgl,
    BoundaryConstants::ALT_TYPE_MSL             =>  altAmsl,
    BoundaryConstants::ALT_TYPE_FLIGHT_LEVEL    =>  altFL,
    BoundaryConstants::ALT_TYPE_BY_NOTAM        =>  altNotam,
);

=head1 NAME

CoPilot::FlightMaster - Parse FlightMaster Airspace database files.

=head1 SYNOPSIS

    use CoPilot::FlightMaster;

    $pdb = new CoPilot::FlightMaster;
    $pdb->Load("airspace.pdb");

    # Manipulate records in $pdb

    $pdb->Write("newairspace.pdb");

=head1 DESCRIPTION

The CoPilot::FlightMaster is a helper class for the Palm::PDB package.  It
provides a framework for reading and writing database files for use with the
Palm Pilot flight software B<FlightMaster>.  For more information on
FlightMaster, see C<http://www.flight-master.com/>.

=head2 AppInfo block

There is no AppInfo block in this database.

=head2 Sort block

    $pdb->{sort}

There is no sort block in this database.

=head2 Records

    $record = $pdb->{records}[N];

=head1 METHODS

=cut

my $EPOCH_1904 = 2082844800;		# Difference between Palm's
					# epoch (Jan. 1, 1904) and
					# Unix's epoch (Jan. 1, 1970),
					# in seconds.

# Assume values already normalized (between -180 and +180 for long, -90
# and +90 for lat)
sub deg2Int32($)
{
    my $deg = shift;
    my $int32 = $deg / 180 * 2**31;
    return int($int32 + .5 * ($int32 <=> 0));
}

# Assume values already normalized (between -180 and +180 for long, -90
# and +90 for lat)
sub deg2Int16($)
{
    my $deg = shift;
    my $int16 = $deg / 180 * 2**15;
    return int($int16 + .5 * ($int16 <=> 0));
}

# Takes an int32 latitude and returns the cell number "row"
sub latcell($)
{
    use integer;
    my $lat = shift;
    return (($lat >> 18) + 4095) & 0xff80;
}

# Takes an int32 longitude and returns the cell number "column"
sub longcell($)
{
    use integer;
    my $long = shift;
    return ($long >> 25) + 64;
}

sub import
{
  &Palm::PDB::RegisterPDBHandlers(__PACKAGE__,
	  [ "BHMN", "airs" ],
	  [ "BHMN", "tfrs" ],
	  [ "GPFM", "airs" ],
	  [ "GPFM", "tfrs" ],
	  );
}

=head2 new

  $pdb = new CoPilot::FlightMaster();

Create a new PDB, initialized with the various CoPilot::FlightMaster fields
and an empty record list.

Use this method if you're creating a FlightMaster PDB from scratch.

=cut
#'

# new
# Create a new CoPilot::FlightMaster database, and return it
sub new
{
  my $classname	= shift;
  my $self	= $classname->SUPER::new(@_);
		  # Create a generic PDB. No need to rebless it,
		  # though.

  $self->{name} = "FlightMaster";	# Default
  $self->{version} = 0;
  $self->{creator} = "GPFM";
  $self->{type} = "airs";
  $self->{attributes}{resource} = 0;
			  # The PDB is not a resource database by
			  # default, but it's worth emphasizing,
			  # since the waypoint database is explicitly not a
			  # PRC.

  # Initialize the AppInfo block
  $self->{appinfo} = undef;

  # Give the PDB an undefined sort block
  $self->{sort} = undef;

  # The first 8196 are taken
  for (my $i = 0; $i < 8197; $i++)
  {
      $self->{records}[$i] = [];
  }

  return $self;
}

=head2 new_Record

  $record = $pdb->new_Record;

Creates a new FlightMaster record, with blank values for all of the fields.

C<new_Record> does B<not> add the new record to C<$pdb>. For that,
you want C<$pdb-E<gt>append_Record>.

=cut

sub new_Record
{
  my $classname = shift;
  my $retval = $classname->SUPER::new_Record(@_);

  $retval->{type} = 0;
  $retval->{extra} = 0;
  $retval->{lowerAlt} = 0;
  $retval->{upperAlt} = 0;
  $retval->{lowerAltRef} = 0;
  $retval->{upperAltRef} = 0;

  return $retval;
}

=head2 create_Record
  $record = $pdb->create_Record($id, $type, $class,
        $min_latitude, $min_longitude,
        $max_latitude, $max_longitude,
        $ownerid,
        $alt_limit_top, $alt_limit_top_type,
        $alt_limit_bottom, $alt_limit_bottom_type,
        $datasource, $frequency, $name);

  Create a record and stick it in the PDB file's record list.  This does
  some of the function's of the parent class new__Record and some of the
  functions of the parent class append_Record.

  Note: Some of these arguments aren't used by FlightMaster, but I'm
  including them because they might be handy later.  Items are given in
  the format and type used by the load scripts, and converted to the
  appropriate FlightMaster formats and types here.  The segments are not
  put in here - they are added later by other methods.

  Arguments:
    $id - SUA id.
    $type - Values in BoundaryConstants::BDRY_TYPE_*
    $class - Letter in 'A', 'B', etc for ICAO airspaces.
    ${min,max}_{lat,long}itude - decimal degrees.
    $ownerid - ID of the airport or waypoint that this SUA or airspace
        protects, if any.
    $alt_limit_{top,bottom} - altitude in feet.
    $alt_limit_{top,bottom}_type - type from BoundaryConstants::ALT_TYPE_*
    $datasource - From Datasources::DATASOURCE_*
    $frequency - decimal frequency for the airspace.
    $name - name of the airspace.

Assigns an ARN (Airspace Record Number) based on its position in the list.

Stores the full extents and the type in records 8192-8196.

The other parameters are stored in the record.

=cut

sub create_Record($$$$$$$$$$$$$$$$)
{
    my ($self, $id, $type, $class,
        $min_latitude, $min_longitude,
        $max_latitude, $max_longitude,
        $ownerid,
        $alt_limit_bottom, $alt_limit_bottom_type,
        $alt_limit_top, $alt_limit_top_type,
        $datasource, $frequency, $name) = @_;

    my $record = $self->new_Record();
    $self->append_Record($record);
	my $ARN = scalar(@{$self->{records}}) - 8198;
print "record id = $id, name = $name, ARN = $ARN\n";

    $record->{ARN} = $ARN;
    # Translate the database type to the flight master type
    my $ltype = 0;
    if (!defined($class) || $class eq "")
    {
        $ltype = $typeTranslations{$type};
        if (!defined($ltype))
        {
            $ltype = asTypeOther;
        }
    }
    elsif ($class eq 'A')
    {
        $ltype = asTypeClassA|asClassA;
    }
    elsif ($class eq 'B')
    {
        $ltype = asTypeClassBG|asClassB;
    }
    elsif ($class eq 'C')
    {
        $ltype = asTypeClassBG|asClassC;
    }
    elsif ($class eq 'D')
    {
        $ltype = asTypeClassBG|asClassD;
    }
    elsif ($class eq 'E')
    {
        $ltype = asTypeClassBG|asClassE;
    }
    elsif ($class eq 'F')
    {
        $ltype = asTypeClassBG|asClassF;
    }
    elsif ($class eq 'G')
    {
        $ltype = asTypeClassBG|asClassG;
    }
    else
    {
        die "unknown class $class\n";
    }
    $record->{type} = $ltype;
print "type = $ltype\n";
	push @{$self->{records}[8196]}, $ltype;

    # Convert the extents to int16 and store them
    my $lmin_latitude = deg2Int16($min_latitude);
    my $lmin_longitude = deg2Int16($min_longitude);
    my $lmax_latitude = deg2Int16($max_latitude);
    my $lmax_longitude = deg2Int16($max_longitude);
print "extents given as ($min_latitude, $min_longitude),",
"($max_latitude, $max_longitude)\n";
print "storing extents as ($lmin_latitude, $lmin_longitude),",
"($lmax_latitude, $lmax_longitude)\n";
	push @{$self->{records}[8192]}, $lmax_latitude;
	push @{$self->{records}[8193]}, $lmax_longitude;
	push @{$self->{records}[8194]}, $lmin_latitude;
	push @{$self->{records}[8195]}, $lmin_longitude;

    # Convert the frequency if given
    my $extra = 0;
    if (defined($frequency) && $frequency ne "")
    {
        my $lIntPart = int($frequency);
        my $lRealPart = int(($frequency - $lIntPart) * 100);
        $extra = ($lIntPart << 8) + $lRealPart;
print "converted frequency $frequency to $lIntPart and $lRealPart, ",
"which becomes $extra\n";
    }
    $record->{extra} = $extra;

    # Convert and store the altitudes
    $record->{lowerAlt} = $alt_limit_bottom;
    $record->{upperAlt} = $alt_limit_top;
    $record->{lowerAltRef} = $altTranslations{$alt_limit_bottom_type};
    $record->{upperAltRef} = $altTranslations{$alt_limit_top_type};
print "altitudes $alt_limit_top/$alt_limit_bottom, orig types ",
"$alt_limit_top_type/$alt_limit_bottom_type become ",
$record->{upperAltRef}, "/", $record->{lowerAltRef}, "\n";

    $record->{description} = "$id - $name";
    $record->{segments} = [];

    return $record;
}

# Internal routine to add extents to the index
#
# Arguments:
#   $ARN    - Airspace Record Number
#   ${start,end}_{lat,long}itude - Int32 degrees.
sub _storeExtents($$$$$$)
{
    my ($self, $ARN, $start_latitude, $start_longitude,
        $end_latitude, $end_longitude) = @_;
print "storing $ARN extents ($start_latitude, $start_longitude) - ",
"($end_latitude, $end_longitude)\n";
    if ($start_latitude > $end_latitude)
    {
        ($start_latitude, $end_latitude) = ($end_latitude, $start_latitude);
    }
    if ($start_longitude > $end_longitude)
    {
        ($start_longitude, $end_longitude) = ($end_longitude, $start_longitude);
    }
    my $startLatCell = latcell($start_latitude);
    my $startLongCell = longcell($start_longitude);
    my $endLatCell = latcell($end_latitude);
    my $endLongCell = longcell($end_longitude);
print "lat cells from $startLatCell to $endLatCell\n";
print "long cells from $startLongCell to $endLongCell\n";
    for (my $row = $startLatCell;
            $row <= $endLatCell;
            $row+=128)
    {
        for (my $col = $startLongCell;
                $col <= $endLongCell;
                $col++)
        {
            my $cell = $row + $col;
            my $cellRef = $self->{records}[$cell];
print "num: $#{$cellRef}\n";
print "before: cellRef for $cell = ", Dumper($cellRef), "\n";
            if ($#{$cellRef} < 0 || $cellRef->[$#{$cellRef}] != $ARN)
            {
print "last: ", $#{$cellRef} < 0 ? -1 : $cellRef->[$#{$cellRef}], "\n";
print "pushing ARN on cell $cell\n";
                push(@{$cellRef}, $ARN);
print "after: cellRef for $cell = ", Dumper($self->{records}[$cell]), "\n";
            }
            else
            {
print "ARN already on cell $cell\n";
            }
        }
    }
}

# Internal routine to get the end coordinates of the last segment
#
# Arguments:
#   $record - Record to get the last record from
#
# Returns:
#   ($latitude,$longitude) - Coordinates of the last point of the previous
#   record, Int32 format.
sub _lastCoordinates($)
{
    my ($record) = @_;

    my ($lat, $long) = (undef, undef);

    my $segmentRef = $record->{segments};
    if ($#{$segmentRef} > 0)
    {
        my $lastSegment = $segmentRef->[$#{$segmentRef}];
        if ($lastSegment->{type} eq segLine)
        {
            $lat = $lastSegment->{lat};
            $long = $lastSegment->{lon};
        }
        elsif ($lastSegment->{type} eq segArc)
        {
            $lat = $lastSegment->{endLatitude};
            $long = $lastSegment->{endLongitude};
        }
    }
    return ($lat, $long);
}

# Internal routine to determine if two coordinates are the same, within
# tolerances.  With Int32 coordinates, coordinates are considered the same
# if they are within 2000, a totally arbitrary figure.
#
# Arguments:
#   $(old,new)_{lat,long}itude - Latitudes and Longitudes in Int32
#
# Returns:
#   1 if they're the same, 0 if they're not.
sub _closeCoordinates($$$$)
{
    my ($old_latitude, $old_longitude, $new_latitude, $new_longitude) = @_;
    if (defined($old_latitude) && defined($old_longitude) &&
        defined($new_latitude) && defined($new_longitude) &&
        abs($old_latitude-$new_latitude) < 2000 &&
        abs($old_longitude-$new_longitude) < 2000)
    {
        return 1;
    }
    return 0;
}

=head2 add_Line
  $pdb->add_Line($record,
        $start_latitude, $start_longitude,
        $end_latitude, $end_longitude);

  Add a line segment to the record

  Note: Items are given in the format and type used by the load scripts,
  and converted to the appropriate FlightMaster formats and types here.

  Arguments:
    $record - Record created by $pdb->create_Record
    ${start,end}_{lat,long}itude - decimal degrees.

  If there is no previous segment then the start lat/long is added as a
  segment.  The end lat/long is added regardless.  The segment type of 'l'
  is appended to the record's segmentCode array.

  Loop through the grids from the minimum latitude and longitude of the
  start and the end to the maximum latitude and longitude
    - If the array for that grid's index record doesn't end with
      this record's ARN, then append the ARN to the array.

=cut

sub add_Line($$$$$$)
{
    my ($self, $record, 
        $start_latitude, $start_longitude,
        $end_latitude, $end_longitude) = @_;

    my $ARN = $record->{ARN};
    my $segmentsRef = $record->{segments};
print "adding line from ($start_latitude, $start_longitude) to ",
"($end_latitude, $end_longitude)\n";
    my $lstart_latitude = deg2Int32($start_latitude);
    my $lstart_longitude = deg2Int32($start_longitude);
    my $lend_latitude = deg2Int32($end_latitude);
    my $lend_longitude = deg2Int32($end_longitude);
print "converted to ($lstart_latitude, $lstart_longitude) to ",
"($lend_latitude, $lend_longitude)\n";

    my ($prevLat, $prevLong) = _lastCoordinates($record);
    if (!_closeCoordinates($prevLat, $prevLong, 
            $lstart_latitude, $lstart_longitude))
    {
print "coordinates aren't close, adding start\n";
        my $segmentRef = {
            "type"      =>  segLine,
            "lat"       =>  $lstart_latitude,
            "lon"       =>  $lstart_longitude,
            };
        push @{$segmentsRef}, $segmentRef;
    }

    my $segmentRef = {
        "type"      =>  segLine,
        "lat"       =>  $lend_latitude,
        "lon"       =>  $lend_longitude,
        };
    push @{$segmentsRef}, $segmentRef;

    $self->_storeExtents($ARN, $lstart_latitude, $lstart_longitude,
            $lend_latitude, $lend_longitude);
}

=head2 add_Arc
  $pdb->add_Arc($record, $type,
        $center_latitude, $center_longitude,
        $start_latitude, $start_longitude, $start_bearing,
        $end_latitude, $end_longitude, $end_bearing,
        $radius,
        $min_latitude, $min_longitude, 
        $max_latitude, $max_longitude);

  Add a arc or circle segment to the record

  Note: Items are given in the format and type used by the load scripts,
  and converted to the appropriate FlightMaster formats and types here.

  Arguments:
    $record - Record created by $pdb->create_Record
    $center_{lat,long}itude - decimal degrees.
    ${start,end}_{lat,long}itude - decimal degrees.
    ${start,end}_bearing - decimal degrees.
    $radius - Radius of the arc in nautical miles.
    ${min,max}_{lat,long}itude - Extents in decimal degrees.

  If there is no previous segment then the start lat/long is added as a
  segment.  Then the segment center, radius, and start and end angles are
  added to the segment record.

=cut

sub add_Arc($$$$$$)
{
    my ($self, $record, $type,
        $center_latitude, $center_longitude,
        $start_latitude, $start_longitude, $start_bearing,
        $end_latitude, $end_longitude, $end_bearing,
        $radius,
        $min_latitude, $min_longitude, 
        $max_latitude, $max_longitude) = @_;

    my $ARN = $record->{ARN};
    my $segmentsRef = $record->{segments};

    my $lstart_latitude = deg2Int32($start_latitude);
    my $lstart_longitude = deg2Int32($start_longitude);
    my ($prevLat, $prevLong) = _lastCoordinates($record);
    if (!_closeCoordinates($prevLat, $prevLong, 
            $lstart_latitude, $lstart_longitude))
    {
print "coordinates aren't close, adding start\n";
        my $segmentRef = {
            "type"      =>  segLine,
            "lat"       =>  $lstart_latitude,
            "lon"       =>  $lstart_longitude,
            };
        push @{$segmentsRef}, $segmentRef;
    }

    my $lradius = (pi/(180*60)) * $radius;

    if ($type == BoundaryConstants::SEGMENT_TYPE_CCW_ARC)
    {
        $lradius = -$lradius;
    }

    my $segmentRef = {
        "type"      =>  segArc,
        "lat"       =>  deg2Int32($center_latitude),
        "long"      =>  deg2Int32($center_longitude),
        "radius"    =>  $lradius,
        "start"     =>  deg2Int16($start_bearing),
        "end"       =>  deg2Int16($end_bearing),
        "endLatitude"   => deg2Int32($end_latitude),
        "endLongitude"   => deg2Int32($end_longitude),
    };
    push @{$segmentsRef}, $segmentRef;

    $self->_storeExtents($ARN,
            deg2Int32($min_latitude), deg2Int32($min_longitude),
            deg2Int32($max_latitude), deg2Int32($max_longitude));
}

=head2 ParseAppInfoBlock

  $appinfo = $pdb->ParseAppInfoBlock($buf);

Takes a blob of raw data in C<$buf>, and parses it into a hash with the data
that we store in the AppInfo block, and returns that hash.

The return value from ParseAppInfoBlock() will be accessible as
$pdb->{appinfo}.

=cut

# ParseAppInfoBlock
# Parse the AppInfo block for FlightMaster databases.
sub ParseAppInfoBlock
{
  my $self = shift;
  my $data = shift;

  return undef;
}

=head2 PackAppInfoBlock

  $buf = $pdb->PackAppInfoBlock();

This is the converse of ParseAppInfoBlock(). It takes $pdb's AppInfo
block, $pdb->{appinfo}, and returns a string of binary data
that can be written to the database file.

=cut

sub PackAppInfoBlock
{
  my $self = shift;

  return undef;
}

=head2 PackSortBlock

  $buf = $pdb->PackSortBlock();

We don't use sort info in this database, so we return an C<undef>.

=cut

sub PackSortBlock
{
  my $self = shift;

  return undef;
}

=head2 ParseRecord

  $record = $pdb->ParseRecord(
          offset         => $offset,	# Record's offset in file
          attributes     =>		# Record attributes
              {
        	expunged => bool,	# True iff expunged
        	dirty    => bool,	# True iff dirty
        	deleted  => bool,	# True iff deleted
        	private  => bool,	# True iff private
              },
          category       => $category,	# Record's category number
          id             => $id,	# Record's unique ID
          data           => $buf,	# Raw record data
        );

ParseRecord() takes the arguments listed above and parses out the various
fields of the record from the C<data> field in the argument.  It adds those
fields to the hash passed in, and returns a reference to that hash.

The output from ParseRecord() will be appended to
@{$pdb->{records}}. The records appear in this list in the
same order as they appear in the file.

=cut

sub ParseRecord
{
  my $self = shift;
  my %record = @_;

  my $index = $record{index};

  # Parse the record depending on what record number it is
  if ($index < 8197)
  {
      # The index records are lists of UInt16s
      my @data = unpack("n*", $record{data});
      push $record{ARNs}, @data;
  }
  else
  {
      # The other records are more complicated
      my ($type, $extra, $lowerAlt, $upperAlt, $lowerAltRef, $upperAltRef,
          $segmentCode, $description, $rest) =
          unpack("nnnnNNZ*Z*a*", $record{data});
      $record{type} = $type;
      $record{extra} = $extra;
      $record{lowerAlt} = $lowerAlt;
      $record{upperAlt} = $upperAlt;
      $record{lowerAltRef} = $lowerAltRef;
      $record{upperAltRef} = $upperAltRef;
      $record{description} = $description;
      $record{segments} = [];

      @segmentCodes = split("", $segmentCode);
      foreach my $segmentType (@segmentCodes)
      {
          if ($segmentType eq segLine)
          {
              my ($lat, $long);
              ($lat, $long, $rest) = unpack("NNa*", $rest);
              # Convert UInt32 to Int32:
              $lat = 
              my $segmentRef = {
                  "type"    =>  segLine,
                  "lat"     =>  
                  "long"    =>
      }
  }
  delete $record{offset};		# This is useless
  delete $record{data};		# This is useless

  return \%record;
}

=head2 PackRecord

  $buf = $pdb->PackRecord($record);

The converse of ParseRecord(). PackRecord() takes a record as returned
by ParseRecord() and returns a string of raw data that can be written
to the database file.

=cut

sub PackRecord
{
  my $self = shift;
  my $record = shift;

=start
  my $packstring = 	$record->{waypoint_id} . "\0" .
			$record->{name} . "\0" .
			$record->{notes} . "\0";
  my $recstring;
  if ($self->{version} == 3)
  {
      $packstring .= $record->{spare} . "\0";

      $recstring = pack("d d d d C a*",
			parseDouble($record->{lat} / $conv),
			parseDouble($record->{long} / $conv),
			parseDouble($record->{decl} / $conv),
			parseDouble($record->{elev}),
            $record->{flags},
			$packstring);
  }
  else
  {
      $recstring = pack("d d f f a*",
			parseDouble($record->{lat} / $conv),
			parseDouble($record->{long} / $conv),
			parseFloat($record->{decl} / $conv),
			parseFloat($record->{elev}),
			$packstring);
  }
  return $recstring;
=cut
}

__END__

=head1 BUGS

These functions die too easily. They should return an error code.

=head1 AUTHOR

Paul Tomblin E<lt>ptomblin@xcski.comE<gt>

=head1 SEE ALSO

Palm::PDB(3)

F<Palm Database Files>, in the ColdSync distribution.

