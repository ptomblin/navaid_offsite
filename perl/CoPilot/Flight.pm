# CoPilot::Flight.pm
#
# Perl class for dealing with CoPilot Flight databases
#
#	Copyright (C) 2001, Paul Tomblin
#	You may distribute this file under the terms of the Clarified Artistic
#	License, as specified in the LICENSE file.
#
# $Id$

use strict;
package CoPilot::Flight;
use Palm::Raw();
use Config;
use vars qw( $VERSION @ISA );

$VERSION = (qw( $Revision: 1.0 $ ))[1];
@ISA = qw( Palm::Raw );

=head1 NAME

CoPilot::Flight - Parse CoPilot Flight database files.

=head1 SYNOPSIS

    use CoPilot::Flight;

    $pdb = new CoPilot::Flight;
    $pdb->Load("flight.pdb");

    # Manipulate records in $pdb

    $pdb->Write("newflight.pdb");

=head1 DESCRIPTION

The CoPilot::Flight is a helper class for the Palm::PDB package.  It
provides a framework for reading and writing database files for use with the
Palm Pilot flight planning software B<CoPilot>.  For more information on
CoPilot, see C<http://xcski.com/~ptomblin/CoPilot/>.

=head2 AppInfo block

There is no AppInfo block on the Flight database.

=head2 Sort block

    $pdb->{sort}

There is no Sort block in this database.

=head2 Records

    $record = $pdb->{records}[N];

    $record->{aircraft}

The uid for the aircraft in the aircraft database.

    $record->{pilot}

The uid for the pilot in the pilot database.

    $record->{route}

The uid for the route in the route database.

    $record->{wb}

The uid for the weight and balance in the weight and balance database.

    $record->{flightplan}

The uid for the flightplan in the flightplan database.

    $record->{date}

Date of the flight.

    $record->{description}

Flight description.

    $record->{note}

Note text.

=head1 METHODS

=cut

my $EPOCH_1904 = 2082844800;		# Difference between Palm's
					# epoch (Jan. 1, 1904) and
					# Unix's epoch (Jan. 1, 1970),
					# in seconds.
my $conv = 180.0 / 3.1415926535898;	# convert degrees to radians.

#my $wpid_len    = 10;
#my $name_len    = 100;
my $notes_len   = 1000;
#my $spare_len   = 30;

sub import
{
  &Palm::PDB::RegisterPDBHandlers(__PACKAGE__,
	  [ "GXBU", "Flgt" ],
	  );
}

=head2 new

  $pdb = new CoPilot::Flight();

Create a new PDB, initialized with the various CoPilot::Flight fields
and an empty record list.

Use this method if you're creating a Flight PDB from scratch.

=cut
#'

# new
# Create a new CoPilot::Flight database, and return it
sub new
{
  my $classname	= shift;
  my $self	= $classname->SUPER::new(@_);
		  # Create a generic PDB. No need to rebless it,
		  # though.

  $self->{name} = "Flight - GXBU";	# Default
  $self->{version} = 0;
  $self->{creator} = "GXBU";
  $self->{type} = "Flgt";
  $self->{attributes}{resource} = 0;
			  # The PDB is not a resource database by
			  # default, but it's worth emphasizing,
			  # since the waypoint database is explicitly not a
			  # PRC.

  # Initialize the AppInfo block
  $self->{appinfo} = undef;

  # Give the PDB an undefined sort block
  $self->{sort} = undef;

  # Give the PDB an empty list of records
  $self->{records} = [];

  return $self;
}

=head2 new_Record

  $record = $pdb->new_Record;

Creates a new Flight record, with blank values for all of the fields.

C<new_Record> does B<not> add the new record to C<$pdb>. For that,
you want C<$pdb-E<gt>append_Record>.

=cut

sub new_Record
{
  my $classname = shift;
  my $retval = $classname->SUPER::new_Record(@_);

  $retval->{aircraft}   = 0;
  $retval->{pilot}      = 0;
  $retval->{route}      = 0;
  $retval->{wb}         = 0;
  $retval->{flightplan} = 0;
  $retval->{date}       = time();
  $retval->{description}= "";
  $retval->{note}       = "";
  $retval->{id} = 0;
  delete $retval->{offset};		# This is useless
  delete $retval->{category};	# This is useless
  delete $retval->{data};		# This is useless

  return $retval;
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
    # Make sure the strings aren't too long for the record.
    $recordref->{notes} =
                substr($recordref->{note}, 0, $notes_len);

    push(@args, $recordref);
  }
  return $self->SUPER::append_Record(@args);
}

=head2 PackAppInfoBlock

We don't have one.

=cut

sub PackAppInfoBlock
{
  return undef;
}

=head2 PackSortBlock

  $buf = $pdb->PackSortBlock();

We don't use sort info in this database, so we return an C<undef>.

=cut

sub PackSortBlock
{
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

  my ($aircraft, $pilot, $route, $wb, $plan, $date, $rest) =
	  unpack("N N N N N N a*", $record{data});
  my ($description, $note) = split(/\0/,$rest);

  $record{aircraft}     = $aircraft;
  $record{pilot}        = $pilot;
  $record{route}        = $route;
  $record{wb}           = $wb;
  $record{flightplan}   = $plan;
  $record{date}         = ($date * 24 * 60 * 60) - $EPOCH_1904;
  $record{description}  = $description;
  $record{note}         = $note;
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

=cut

sub PackRecord
{
  my $self = shift;
  my $record = shift;

  my $packstring = 	
			$record->{description} . "\0" .
			$record->{note} . "\0";
  my $recstring =
	  pack("N N N N N N a*",
			$record->{aircraft},
			$record->{pilot},
			$record->{route},
			$record->{wb},
			$record->{flightplan},
			($record->{date}/24/60/60) + $EPOCH_1904,
			$packstring);
  return $recstring;
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

