# CoPilot::Waypoint.pm
#
# Perl class for dealing with CoPilot Waypoint databases
#
#	Copyright (C) 2001, Paul Tomblin
#	You may distribute this file under the terms of the Clarified Artistic
#	License, as specified in the LICENSE file.
#
# $Id: Waypoint.pm,v 1.14 2006/01/05 23:05:58 navaid Exp navaid $

use strict;
package CoPilot::Waypoint;
use Palm::Raw();
use Config;
use vars qw( $VERSION @ISA );

$VERSION = (qw( $Revision: 1.14 $ ))[1];
@ISA = qw( Palm::Raw );

=head1 NAME

CoPilot::Waypoint - Parse CoPilot Waypoint database files.

=head1 SYNOPSIS

    use CoPilot::Waypoint;

    $pdb = new CoPilot::Waypoint;
    $pdb->Load("waypoint.pdb");

    # Manipulate records in $pdb

    $pdb->Write("newwaypoint.pdb");

=head1 DESCRIPTION

The CoPilot::Waypoint is a helper class for the Palm::PDB package.  It
provides a framework for reading and writing database files for use with the
Palm Pilot flight planning software B<CoPilot>.  For more information on
CoPilot, see C<http://xcski.com/~ptomblin/CoPilot/>.

=head2 AppInfo block

The AppInfo block has information to be displayed in the
Options->"Waypoint Info" menu of B<CoPilot>.
The fields are:

    $pdb->{appinfo}{version}

The appinfo block version.  Currently 0.

    $pdb->{appinfo}{creationDate}

The date that the database was created.  In a new database it's initialized to
the current time.  If you're updating an existing database, you might want to
reinitialize it to the current time.

    $pdb->{appinfo}{infoString}

A string telling the user who generated the database and where they can find
the most up-to-date version.

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

Extra stuff.  Currently I put in whether the waypoint is an airport or a
navaid, and if a navaid its frequency.  When I've got better data, I'd like to
put in runway lengths and frequencies for airports.

    $record->{spare}

This currently isn't used by CoPilot.

=head1 METHODS

=cut

my $EPOCH_1904 = 2082844800;		# Difference between Palm's
					# epoch (Jan. 1, 1904) and
					# Unix's epoch (Jan. 1, 1970),
					# in seconds.
my $conv = 180.0 / 3.1415926535898;	# convert degrees to radians.

my $wpid_len    = 10;
my $name_len    = 100;
my $notes_len   = 1000;
my $spare_len   = 30;

my $swabit = $Config{byteorder} eq '1234' || $Config{byteorder} eq '12345678';

sub import
{
  &Palm::PDB::RegisterPDBHandlers(__PACKAGE__,
	  [ "GXBU", "wayp" ],
	  [ "GXBU", "swpu" ],
	  [ "AP-P", "wayp" ],
	  [ "AP-P", "swpu" ],
	  );
}

=head2 new

  $pdb = new CoPilot::Waypoint();

Create a new PDB, initialized with the various CoPilot::Waypoint fields
and an empty record list.

Use this method if you're creating a Waypoint PDB from scratch.

=cut
#'

# new
# Create a new CoPilot::Waypoint database, and return it
sub new
{
  my $classname	= shift;
  my $self	= $classname->SUPER::new(@_);
		  # Create a generic PDB. No need to rebless it,
		  # though.

  $self->{name} = "CoPilot Waypoint";	# Default
  $self->{version} = 4;
  $self->{creator} = "GXBU";
  $self->{type} = "wayp";
  $self->{attributes}{resource} = 0;
			  # The PDB is not a resource database by
			  # default, but it's worth emphasizing,
			  # since the waypoint database is explicitly not a
			  # PRC.

  # Initialize the AppInfo block
  $self->{appinfo} = {
	  version       => 0,
	  creationDate	=> time(),
	  infoString	=>
	    "CoPilot WayPoint Database\nCreated by Paul Tomblin\n" .
	    "http://navaid.com/CoPilot/\n"
  };

  # Give the PDB an undefined sort block
  $self->{sort} = undef;

  # Give the PDB an empty list of records
  $self->{records} = [];

  return $self;
}

=head2 new_Record

  $record = $pdb->new_Record;

Creates a new Waypoint record, with blank values for all of the fields.

C<new_Record> does B<not> add the new record to C<$pdb>. For that,
you want C<$pdb-E<gt>append_Record>.

=cut

sub new_Record
{
  my $classname = shift;
  my $retval = $classname->SUPER::new_Record(@_);

  $retval->{lat} = 0.0;
  $retval->{long} = 0.0;
  $retval->{decl} = 0.0;
  $retval->{elev} = 0.0;
  $retval->{waypoint_id} = "";
  $retval->{name} = "";
  $retval->{notes} = "";
  $retval->{spare} = "";
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
    if ($recordref->{id} == 0)
    {
      $recordref->{id} = encodeid($recordref->{waypoint_id});
    }

    # Make sure the strings aren't too long for the record.
    $recordref->{waypoint_id} =
                substr($recordref->{waypoint_id}, 0, $wpid_len);
    $recordref->{name} =
                substr($recordref->{name}, 0, $name_len);
    $recordref->{notes} =
                substr($recordref->{notes}, 0, $notes_len);
    $recordref->{spare} =
                substr($recordref->{spare}, 0, $spare_len);

    push(@args, $recordref);
  }
  return $self->SUPER::append_Record(@args);
}

=head2 ParseAppInfoBlock

  $appinfo = $pdb->ParseAppInfoBlock($buf);

Takes a blob of raw data in C<$buf>, and parses it into a hash with the data
that we store in the AppInfo block, and returns that hash.

The return value from ParseAppInfoBlock() will be accessible as
$pdb->{appinfo}.

=cut

# ParseAppInfoBlock
# Parse the AppInfo block for Waypoint databases.
sub ParseAppInfoBlock
{
  my $self = shift;
  my $data = shift;
  my $appinfo = {};

  # Get the rest of the AppInfo block
  my $unpackstr =	# Argument to unpack()
	  "n" .	    	# version
	  "N" .		# date in seconds
	  "Z*";		# info string

  my ($version, $creationDate, $infoString) = unpack $unpackstr, $data;

  $appinfo->{version}	    = $version;
  $appinfo->{creationDate}	= $creationDate - $EPOCH_1904;
  $appinfo->{infoString}	= $infoString;

  return $appinfo;
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
  if (!exists($self->{appinfo}) || !exists($self->{appinfo}{version}))
  {
    $self->{appinfo} = {
	    version		=> 0,
	    creationDate	=> time(),
	    infoString		=>
	      "CoPilot WayPoint Database\nCreated by Paul Tomblin\n" .
	      "http://xcski.com/~ptomblin/CoPilot/\n"
    };
  }



  # Pack the non-category part of the AppInfo block
  $self->{appinfo}{other} =
	  pack("n N Z*",
              $self->{appinfo}{version},
			  $self->{appinfo}{creationDate} + $EPOCH_1904,
			  $self->{appinfo}{infoString});

  return $self->{appinfo}{other};
}

=head2 PackSortBlock

  $buf = $pdb->PackSortBlock();

We don't use sort info in this database, so we return an C<undef>.

=cut

sub PackSortBlock
{
  my $self = shift;

  # Change the header to the current one.
  #$self->{name} = "CoPilot Waypoint"; # Default
  #$self->{version} = 3;

  # This is a bit of a kludge, but the record array must be sorted, and this
  # is a good place to sort it before we write it.
  my $recordsArrRef = $self->{records};
  my @newrecs = sort { $a->{waypoint_id} cmp $b->{waypoint_id} }
		    @{$recordsArrRef};
  $self->{records} = \@newrecs;

  return undef;
}

sub parseDouble($)
{
    my $dub = shift;
    if (!$swabit)
    {
        return $dub;
    }
    return unpack("d", pack("C8", reverse(unpack("C8", pack("d", $dub)))));
}


sub parseFloat($)
{
    my $dub = shift;
    if (!$swabit)
    {
        return $dub;
    }
    return unpack("f", pack("C4", reverse(unpack("C4", pack("f", $dub)))));
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

  my ($lat, $long, $decl, $elev, $flags, $rest);
  my ($wpid, $name, $notes, $spare);

  if ($self->{version} == 0)
  {
      ($lat, $long, $decl, $elev, $rest) =
          unpack("d d d N a*", $record{data});
      ($wpid, $name) = split(/\0/,$rest);
      $decl = parseDouble($decl);
      $notes = "";
      $spare = "";
      $flags = 0;
  }
  elsif ($self->{version} == 1 || $self->{version} == 2)
  {
      ($lat, $long, $decl, $elev, $rest) =
          unpack("d d d d a*", $record{data});
      $flags = 0;
      $decl = parseDouble($decl);
      $elev = parseDouble($elev);
      ($wpid, $name, $notes, $spare) = split(/\0/,$rest);
  }
  elsif ($self->{version} == 3)
  {
      ($lat, $long, $decl, $elev, $flags, $rest) =
          unpack("d d d d C a*", $record{data});
      $decl = parseDouble($decl);
      $elev = parseDouble($elev);
      ($wpid, $name, $notes, $spare) = split(/\0/,$rest);
  }
  elsif ($self->{version} == 4)
  {
      ($lat, $long, $decl, $elev, $rest) =
          unpack("d d f f a*", $record{data});
      $flags = "";
      $decl = parseFloat($decl);
      $elev = parseFloat($elev);
      ($wpid, $name, $notes) = split(/\0/,$rest);
      $spare = "";
  }

  $record{lat}  = parseDouble($lat) * $conv;
  $record{long} = parseDouble($long) * $conv;
  $record{decl} = $decl * $conv;
  $record{elev} = $elev;
  $record{flags} = $flags;
  $record{waypoint_id} = $wpid;
  $record{name} = $name;
  $record{notes} = $notes;
  $record{spare} = $spare;
  $record{category} = 0;
# $record{decodedId} = decodeid($record{wpid});
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

=head2 addWaypoint

  $pdb->addWaypoint($lat, $long, $decl, $elev, "KROC", $name, $notes, $spare);

Adds an airport to the record list.

=cut

sub addWaypoint($$$$$$$$)
{
    my ($self,$lat,$long,$decl,$elev,$wpid,$name,$notes,$spare) = @_;
    my $record = $self->new_Record;
    $record->{lat}  = $lat;
    $record->{long} = $long;
    $record->{decl} = $decl;
    $record->{elev} = $elev;
    $record->{flags} = 0;
    $record->{waypoint_id} = $wpid;
    $record->{name} = $name;
    $record->{notes} = $notes;
    $record->{spare} = $spare;
    $self->append_Record($record);
}


=head2 addWaypointWithID

  $pdb->addWaypointWidthID($id, $lat, $long, $decl, $elev, "KROC", $name, $notes, $spare);

Adds an airport to the record list, with a given "unique id".

=cut

sub addWaypointWithID($$$$$$$$$)
{
    my ($self,$id,$lat,$long,$decl,$elev,$wpid,$name,$notes,$spare) = @_;
    my $record = $self->new_Record;
    $record->{id} = $id;
    $record->{lat}  = $lat;
    $record->{long} = $long;
    $record->{decl} = $decl;
    $record->{elev} = $elev;
    $record->{flags} = 0;
    $record->{waypoint_id} = $wpid;
    $record->{name} = $name;
    $record->{notes} = $notes;
    $record->{spare} = $spare;
    $self->append_Record($record);
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

