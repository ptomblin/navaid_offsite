# GPSPilot::Points.pm
#
# Perl class for dealing with GPSPilot Points databases
#
#	Copyright (C) 2001, Paul Tomblin
#	You may distribute this file under the terms of the Clarified Artistic
#	License, as specified in the LICENSE file.
#
# $Id: Points.pm,v 1.5 2002/12/03 03:45:03 ptomblin Exp $

use strict;
package GPSPilot::Points;
use Palm::Raw();
use Config;
use vars qw( $VERSION @ISA );

$VERSION = (qw( $Revision: 1.5 $ ))[1];
@ISA = qw( Palm::Raw );

=head1 NAME

GPSPilot::Points - Parse GPSPilot Points database files.

=head1 SYNOPSIS

    use GPSPilot::Points;

    $pdb = new GPSPilot::Points;
    $pdb->Load("GP_point.pdb");

    # Manipulate records in $pdb

    $pdb->Write("newGP_point.pdb");

=head1 DESCRIPTION

The GPSPilot::Points is a helper class for the Palm::PDB package.  It
provides a framework for reading and writing database files for use with the
Palm Pilot flight planning software B<GPSPilot>.  For more information on
GPSPilot, see C<http://www.gpspilot.com/Fly.htm>.

=head2 AppInfo block

There is no AppInfo block in this database.

=head2 Sort block

    $pdb->{sort}

There is no sort block in this database.

=head2 Records

    $record = $pdb->{records}[N];

    $record->{lat}
    $record->{long}

The latitude and longitude of the waypoint in degrees.  North and West are
positive, South and East are negative.

    $record->{decl}

Magnetic declination in degrees.  West is positive and East is negative.

    $record->{elev}

The elevation of the waypoint.  Leave it 0 if you don't know or don't care.

    $record->{waypoint_id}

A unique id for the waypoint.  By default, the ICAO idenfier.

    $record->{name}

A longer, more descriptive name, such as the waypoint name and state/province
and country.

    $record->{notes}

Extra stuff.

=head1 METHODS

=cut

my $EPOCH_1904 = 2082844800;		# Difference between Palm's
					# epoch (Jan. 1, 1904) and
					# Unix's epoch (Jan. 1, 1970),
					# in seconds.
my $conv = 1.0 / 3600000.0;	# convert milliseconds to degrees.
use constant MAXINT => 2**31-1;
use constant MAXUINT => 2**32;
use constant MAXSHORT => 2**15-1;
use constant MAXUSHORT => 2**16;
use constant FEET_TO_METRES => 0.3048;
my $wpid_len    = 8;
my $name_len    = 35;
my $notes_len   = 160;

sub import
{
  &Palm::PDB::RegisterPDBHandlers(__PACKAGE__,
	  [ "GpLi", "poin" ],
	  [ "GpLi", "po00" ],
	  [ "GpLi", "po01" ],
	  [ "GpLi", "po02" ],
	  [ "GpLi", "po03" ],
	  );
}

=head2 new

  $pdb = new GPSPilot::Points();

Create a new PDB, initialized with the various GPSPilot::Points fields
and an empty record list.

Use this method if you're creating a Points PDB from scratch.

=cut
#'

# new
# Create a new GPSPilot::Points database, and return it
sub new
{
  my $classname	= shift;
  my $self	= $classname->SUPER::new(@_);
		  # Create a generic PDB. No need to rebless it,
		  # though.

  $self->{name} = undef;  # set this in PackSortBlock if the user doesn't
                          # set it.
  $self->{version} = 0;
  $self->{creator} = "GpLi";
  $self->{type} = "po00";
  $self->{typeflags}[0] = 0;
  $self->{typeflags}[1] = 0;
  $self->{typeflags}[2] = 0;
  $self->{typeflags}[3] = 0;

  $self->{attributes}{resource} = 0;
			  # The PDB is not a resource database by
			  # default, but it's worth emphasizing,
			  # since the waypoint database is explicitly not a
			  # PRC.

  # Give the PDB an undefined appinfo block
  $self->{appinfo} = undef;

  # Give the PDB an undefined sort block
  $self->{sort} = undef;

  # Give the PDB an empty list of records
  $self->{records} = [];

  return $self;
}

=head2 new_Record

  $record = $pdb->new_Record;

Creates a new Points record, with blank values for all of the fields.

C<new_Record> does B<not> add the new record to C<$pdb>. For that,
you want C<$pdb-E<gt>append_Record>.

=cut

sub new_Record
{
  my $classname = shift;
  my $retval = $classname->SUPER::new_Record(@_);

  $retval->{lat} = 0.0;
  $retval->{long} = 0.0;
  $retval->{elev} = 0.0;
  $retval->{decl} = 0.0;
  $retval->{runways} = ();
  $retval->{waypoint_id} = "";
  $retval->{name} = "";
  $retval->{notes} = "";
  $retval->{id} = 0;
  $retval->{flags} = 0;
  $retval->{category} = 0;
  delete $retval->{offset};		# This is useless
  delete $retval->{data};		# This is useless

  return $retval;
}

## Internal routines ##
#	Takes up to 4 alphanumeric characters and returns a 3 byte integer
#	packing them in
sub encodeid($)
{
  my $string = shift;
#  $string = uc($string);
  my $len = length($string);
  if ($len > 4)
  {
    return 0;
  }
  my $index;
  my $packed = 0;
  for ($index = 0; $index < $len; $index++)
  {
    my $char = substr($string, $index, 1);
    my $ord = index(
    	" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz",
	$char);
    $packed = ($packed << 6) + $ord;
  }
  return $packed;
}

#	Takes a 24 bit packed decimal and decodes it into alphanumerics
sub decodeid($)
{
  my $packed = shift;
  my $retstring = "";
  while ($packed > 0)
  {
    my $last6 = $packed & 077;
    my $char = substr(
    	" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz",
	$last6, 1);
    $retstring = $char . $retstring;
    $packed = ($packed >> 6);
  }
  return $retstring;
}

=head2 append_Record

  $record = $pdb->append_Record();
  $record2 = $pdb->append_Record($records);

If called without any arguments, creates a new record with
L<new_Record()|/new_Record>, and appends it to $pdb.

If given a reference to one or more records, appends that record to
@{$pdb->{records}}.

This method updates $pdb's "last modification" time.

=cut

# Override the append_Record in the parent class.
sub append_Record
{
  my $self = shift;
  if ($#_ < 0)
  {
    return $self->SUPER::append_Record(@_);
  }
  my @args = ();
  my $recordref;
  foreach $recordref (@_)
  {
    # Encode the waypoint id into the id.
    $recordref->{id} = encodeid($recordref->{waypoint_id});

    # Make sure the strings aren't too long for the record.
    $recordref->{waypoint_id} =
                substr($recordref->{waypoint_id}, 0, $wpid_len);
    $recordref->{name} =
                substr($recordref->{name}, 0, $name_len);
    $recordref->{notes} =
                substr($recordref->{notes}, 0, $notes_len);
    push(@args, $recordref);
  }
  return $self->SUPER::append_Record(@args);
}

=head2 PackAppInfoBlock

  $buf = $pdb->PackAppInfoBlock();

We don't use appinfo in this database, so we return an empty string.

=cut

sub PackAppInfoBlock
{
  my $self = shift;

  return "";
}

=head2 PackSortBlock

  $buf = $pdb->PackSortBlock();

We don't use sort info in this database, so we return an C<undef>.

=cut

sub PackSortBlock
{
  my $self = shift;

  # Change the header to the current one.
  my $changeName = !defined($self->{name});

  $self->{name} = "GPSPilot Points" if ($changeName);

  $self->{version} = 0;
  if (($self->{typeflags}[0] + $self->{typeflags}[1] +
      $self->{typeflags}[2] + $self->{typeflags}[3]) > 1)
  {
      $self->{type} = "poin";
      $self->{name} = "GPSPilot Points" if ($changeName);
  }
  elsif ($self->{typeflags}[0])
  {
      $self->{type} = "po00";
      $self->{name} = "GPSPilot Airports" if ($changeName);
  }
  elsif ($self->{typeflags}[1])
  {
      $self->{type} = "po01";
      $self->{name} = "GPSPilot Cities" if ($changeName);
  }
  elsif ($self->{typeflags}[2])
  {
      $self->{type} = "po02";
      $self->{name} = "GPSPilot Landmarks" if ($changeName);
  }
  elsif ($self->{typeflags}[3])
  {
      $self->{type} = "po03";
      $self->{name} = "GPSPilot Navaids" if ($changeName);
  }

  # This is a bit of a kludge, but the record array must be sorted, and this
  # is a good place to sort it before we write it.
  my $recordsArrRef = $self->{records};
  my @newrecs = sort { -($a->{long} <=> $b->{long}) }
		    @{$recordsArrRef};
  $self->{records} = \@newrecs;

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

sub convLong($)
{
    my $long = shift;
    if ($long > MAXINT)
    {
        return $long - MAXUINT;
    }
    return $long;
}


sub convShort($)
{
    my $short = shift;
    if ($short > MAXSHORT)
    {
        return $short - MAXUSHORT;
    }
    return $short;
}

sub ParseRecord
{
  my $self = shift;
  my %record = @_;

  my ($lat, $long, $decl, $elev, $rest);
  my ($id, $name, $notes, $numRunways, @runways);

  $self->{typeflags}[$self->{category}] = 1;
#  if ($self->{version} == 0)
  ($long, $lat, $elev, $decl, $rest) =
        unpack("N N n n a*", $record{data});
  $record{long} = -convLong($long) * $conv;
  $record{lat}  = convLong($lat) * $conv;
  $record{decl} = -convShort($decl);
  $record{elev} = $elev/FEET_TO_METRES;

  if ($record{category} == 0)
  {
      # Airport record
      ($numRunways, $rest) =
            unpack("n a*", $rest);
      my $i;
      for ($i = 0; $i < $numRunways; $i++)
      {
          my ($belong, $belat, $relong, $relat);
          ($belong, $belat, $relong, $relat, $rest) =
                unpack("N N N N a*", $rest);
          $runways[$i] = { "BeLong" => -convLong($belong) * $conv,
                           "BeLat" => convLong($belat) * $conv,
                           "ReLong" => -convLong($relong) * $conv,
                           "ReLat" => convLong($relat) * $conv, };
      }
  }
  ($id, $name, $notes, $rest) = split(/\0/,$rest, 4);
  $record{flags} = 0;
  $record{waypoint_id} = $id;
  $record{name} = $name;
  $record{notes} = $notes;

  if ($record{category} == 0)
  {
      # Airport record
      my $i;
      for ($i = 0; $i < $numRunways; $i++)
      {
          my $rwyname;
          ($rwyname, $rest) = split(/\0/,$rest, 2);
          $runways[$i]->{RunwayName} = $rwyname;
      }
      $record{runways} = \@runways;
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

  my $numRunways;
  my $runwayref;

  my $packstring = pack("N N n n", 
            -$record->{long} / $conv + 0.5,
            $record->{lat} / $conv + 0.5,
            $record->{elev} * FEET_TO_METRES + 0.5,
            -$record->{decl});
  my $idString;
  if ($record->{category} == 0)
  {
      $runwayref = $record->{runways};
      $numRunways = defined($runwayref) ? scalar(@$runwayref) : 0;
      $packstring .= pack("n", $numRunways);
      my $i;
      for ($i = 0; $i < $numRunways; $i++)
      {
          my ($belong, $belat, $relong, $relat);
          $belong = $runwayref->[$i]{BeLong};
          $belat = $runwayref->[$i]{BeLat};
          $relong = $runwayref->[$i]{ReLong};
          $relat = $runwayref->[$i]{ReLat};
          $packstring .= pack("NNNN",
            -$belong / $conv + 0.5,
            $belat / $conv + 0.5,
            -$relong / $conv + 0.5,
            $relat / $conv + 0.5);
      }
      $idString = 	$record->{waypoint_id} . "\0" .
                $record->{name} . "\0" .
			$record->{notes} . "\0";
  }
  else
  {
      $idString = 	$record->{name} . "\0" .
            $record->{waypoint_id} . "\0" .
			$record->{notes} . "\0";
  }

  $packstring .= $idString;
  if ($record->{category} == 0)
  {
      # Airport record
      my $i;
      for ($i = 0; $i < $numRunways; $i++)
      {
          my $rwyname = $runwayref->[$i]{RunwayName} . "\0";
          $packstring .= $rwyname;
      }
  }
  return $packstring;
}

=head2 getRecord

  $record = $pdb->getRecord("KROC");

Gets an waypoint record by waypoint id.

=cut

sub getRecord($$)
{
    my ($self,$wpid) = @_;
    return (grep { $_->{waypoint_id} eq $wpid } (@{$self->{records}}))[0];
}

=head2 addPoint

  $pdb->addPoint($lat, $long, $decl, $elev, "KROC", $name, $notes, $category);

Adds a point to the record list.

=cut

sub addPoint($$$$$$$$$)
{
    my ($self,$lat,$long,$decl,$elev,$wpid,$name,$notes,$category) = @_;
    my $record = $self->new_Record;
    $record->{lat}  = $lat;
    $record->{long} = $long;
    $record->{decl} = $decl;
    $record->{elev} = $elev;
    $record->{flags} = 0;
    $record->{waypoint_id} = $wpid;
    $record->{name} = $name;
    $record->{notes} = $notes;
    $record->{category} = $category;
    $self->{typeflags}[$category] = 1;
    
    return $self->append_Record($record);
}


=head2 addAirport

  $pdb->addAirport($lat, $long, $decl, $elev, "KROC", $name, $notes);

Adds an airport to the record list.

=cut

sub addAirport($$$$$$$)
{
    my ($self,$lat,$long,$decl,$elev,$wpid,$name,$notes) = @_;
    return addPoint($self, $lat, $long, $decl, $elev, $wpid, $name, $notes, 0);
}


=head2 addNavaid

  $pdb->addNavaid($lat, $long, $decl, $elev, "KROC", $name, $notes);

Adds a navaid to the record list.

=cut

sub addNavaid($$$$$$$)
{
    my ($self,$lat,$long,$decl,$elev,$wpid,$name,$notes) = @_;
    return addPoint($self, $lat, $long, $decl, $elev, $wpid, $name, $notes, 3);
}

=head2 addRunway

  $pdb->addRunway($airport, "7/25", $belat, $belong, $relat, $relong);

Adds a runway to an existing point

=cut

sub addRunway($$$$$$$)
{
    my ($self,$record,$runwayName,$belat,$belong,$relat,$relong) = @_;

    my $runwayRef = {
                        "RunwayName" => $runwayName,
                        "BeLong" => $belong,
                        "BeLat" => $belat,
                        "ReLong" => $relong,
                        "ReLat" => $relat,
                    };
    my $runwayArr = $record->{runways};
    push(@$runwayArr, $runwayRef);
    $record->{runways} = $runwayArr;
}


1;

__END__

=head1 BUGS

These functions die too easily. They should return an error code.

=head1 AUTHOR

Paul Tomblin E<lt>ptomblin@xcski.comE<gt>

=head1 SEE ALSO

Palm::PDB(3)

F<Palm Database Files>, in the ColdSync distribution.

=cut
