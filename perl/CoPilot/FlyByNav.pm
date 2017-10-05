# CoPilot::FlyByNav.pm
#
# Perl class for dealing with FlyByNav databases
#
#	Copyright (C) 2001, Paul Tomblin
#	You may distribute this file under the terms of the Clarified Artistic
#	License, as specified in the LICENSE file.
#
# $Id$

use strict;
package CoPilot::FlyByNav;
use Palm::Raw();
use Palm::StdAppInfo();
use Config;
use vars qw( $VERSION @ISA );

$VERSION = (qw( $Revision: 1.5 $ ))[1];
@ISA = qw( Palm::Raw );

=head1 NAME

CoPilot::FlyByNav - Parse FlyByNav database files.

=head1 SYNOPSIS

    use CoPilot::FlyByNav;

    $pdb = new CoPilot::FlyByNav;
    $pdb->Load("waypoint.pdb");

    # Manipulate records in $pdb

    $pdb->Write("newwaypoint.pdb");

=head1 DESCRIPTION

The CoPilot::FlyByNav is a helper class for the Palm::PDB package.  It
provides a framework for reading and writing database files for use with the
Palm Pilot flight planning software B<FlyByNav>.  It's in the B<CoPilot>
package because I was using this to steal data from a FlyByNav database to use
in a CoPilot database until I could find a better source for data.

=head2 AppInfo block

The AppInfo block has the standard classification data, I believe.  I don't
care, because I'm not going to write these database, only read them.

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

    $record->{type}

The type of the waypoint.  Must be filled in.

    $record->{elev}

The elevation of the waypoint.  Leave it 0 if you don't know or don't care.

    $record->{freq}

The frequency of the waypoint.  Leave it blank if you don't know or don't
care.

    $record->{waypoint_id}

A unique id for the waypoint.  By default, the ICAO idenfier.

    $record->{name}

A longer, more descriptive name for the airport/navaid.

    $record->{state}

The state it resides in.

    $record->{country}

The country it resides in.

=head1 METHODS

=cut

my $EPOCH_1904 = 2082844800;		# Difference between Palm's
					# epoch (Jan. 1, 1904) and
					# Unix's epoch (Jan. 1, 1970),
					# in seconds.
my $conv = 180.0 / 3.1415926535898;	# convert degrees to radians.

sub import
{
  &Palm::PDB::RegisterPDBHandlers(__PACKAGE__,
	  [ "CASL", "USER" ],
	  );
}

=head2 new

  $pdb = new CoPilot::FlyByNav();

Create a new PDB, initialized with the various CoPilot::FlyByNav fields
and an empty record list.

Use this method if you're creating a FlyByNav PDB from scratch.

=cut
#'

# new
# Create a new CoPilot::FlyByNav database, and return it
sub new
{
  my $classname	= shift;
  my $self	= $classname->SUPER::new(@_);
		  # Create a generic PDB. No need to rebless it,
		  # though.

  $self->{name} = "FlyByWyptDB";	# Default
  $self->{version} = 0;
  $self->{creator} = "CASL";
  $self->{type} = "USER";
  $self->{attributes}{resource} = 0;
			  # The PDB is not a resource database by
			  # default, but it's worth emphasizing,
			  # since the waypoint database is explicitly not a
			  # PRC.

  # Initialize the AppInfo block
  &Palm::StdAppInfo::seed_StdAppInfo($self->{appinfo});

  # Give the PDB an undefined sort block
  $self->{sort} = undef;

  # Give the PDB an empty list of records
  $self->{records} = [];

  return $self;
}

=head2 new_Record

  $record = $pdb->new_Record;

Creates a new FlyByNav record, with blank values for all of the fields.

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
  $retval->{type} = "";
  $retval->{name} = "";
  $retval->{state} = "";
  $retval->{country} = "";
  $retval->{id} = 0;
  delete $retval->{offset};		# This is useless
  delete $retval->{category};		# This is useless
  delete $retval->{data};		# This is useless

  return $retval;
}

=head2 ParseAppInfoBlock

  $appinfo = $pdb->ParseAppInfoBlock($buf);

Takes a blob of raw data in C<$buf>, and parses it into a hash with the data
that we store in the AppInfo block, and returns that hash.

The return value from ParseAppInfoBlock() will be accessible as
$pdb->{appinfo}.

=cut

# ParseAppInfoBlock
# Parse the AppInfo block for FlyByNav databases.
sub ParseAppInfoBlock
{
  my $self = shift;
  my $data = shift;
  my $appinfo = {};

  my $std_len = &Palm::StdAppInfo::parse_StdAppInfo($appinfo, $data);

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

  my $retval = &Palm::StdAppInfo::pack_StdAppInfo($self->{appinfo});

  return $retval;
}

=head2 PackSortBlock

  $buf = $pdb->PackSortBlock();

We don't use sort info in this database, so we return an C<undef>.

=cut

sub PackSortBlock
{
  return undef;
}

sub parseDouble($)
{
    my $dub = shift;
    if ($Config{byteorder} ne '1234')
    {
        return $dub;
    }
    return unpack("d", pack("C8", reverse(unpack("C8", pack("d", $dub)))));
}


# Internal routine that takes a string, reads up to the first null and returns
# the bit before the null and the rest.  But if the first string is an odd
# number of bytes long, it skips one byte.  Don't ask me why, I assume it's a
# weird feature of CASL.
sub readEvenString($)
{
    my $data = shift;
    my ($retval, $rest) = split("\0", $data, 2);
    if (defined($rest) && (length($retval) % 2) == 0)
    {
        $rest = substr($rest,1);
    }
    return ($retval, $rest);
}

# Internal routine that takes a string and packs an extra null on the end if
# it's an odd length.  I haven't tested this!
sub packEvenString($)
{
    my $data = shift;
    if ((length($data) % 2) == 0)
    {
        $data = $data . "\0";
    }
    return $data;
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


  my ($id, $rest) = readEvenString($record{data});
  my ($lat, $long, $decl, $rest1) = unpack("d d d A*", $rest);
  my ($type, $rest2) = readEvenString($rest1);
  my ($freq, $rest3) = readEvenString($rest2);
  my ($elev, $rest4) = readEvenString($rest3);
  my ($name, $rest5) = readEvenString($rest4);
  my ($state, $rest6) = readEvenString($rest5);
  my ($country, $rest7) = readEvenString($rest6);

  $record{lat}  = parseDouble($lat);
  $record{long} = parseDouble($long);
  $record{decl} = parseDouble($decl);
  if ($elev eq "-----")
  {
      $elev = "0";
  }
  $record{elev} = $elev;
  $record{waypoint_id} = $id;
  $record{type} = $type;
  $record{freq} = $freq;
  $record{name} = $name;
  $record{state} = $state;
  $record{country} = $country;
  delete $record{offset};		# This is useless
  delete $record{category};	# This is useless
  delete $record{data};		# This is useless

  return \%record;
}

=head2 PackRecord

  $buf = $pdb->PackRecord($record);

The converse of ParseRecord(). PackRecord() takes a record as returned
by ParseRecord() and returns a string of raw data that can be written
to the database file.

Note: I don't need to write these records, so I haven't tested this.
=cut

sub PackRecord
{
  my $self = shift;
  my $record = shift;

  my $packstring = 	packEvenString($record->{waypoint_id}) . "\0" .
            pack("d d d", 
                parseDouble($record->{lat}),
                parseDouble($record->{long}),
                parseDouble($record->{decl})) .
            packEvenString($record->{type}) . "\0" .
            packEvenString($record->{freq}) . "\0" .
            packEvenString($record->{elev}) . "\0" .
            packEvenString($record->{name}) . "\0" .
            packEvenString($record->{state}) . "\0" .
            packEvenString($record->{country}) . "\0";
  return $packstring;
}

=head2 getAirport

  $record = $pdb->getAirport("KROC");

Gets an airport by waypoint id.

=cut

sub getRecord($$)
{
    my ($self,$wpid) = @_;
    return (grep { $_->{waypoint_id} eq $wpid } (@{$self->{records}}))[0];
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

