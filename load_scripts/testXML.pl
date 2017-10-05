#!/usr/bin/perl -w

# EAD AIXM
#

use warnings FATAL => 'all';

use IO::File;
use XML::SAX;

use strict;

$| = 1; # for debugging

use XML::SAX::ParserFactory;

my $eadFile = shift;


package EADHandler;
use base qw(XML::SAX::Base);

sub start_document
{
  my $self = shift;
  print "start document\n";
}

sub start_element
{
  my ($self, $element) = @_;
  my $localName = $element->{"LocalName"};
  print "start element $localName\n";
}

sub end_element
{
  my ($self, $element) = @_;
  my $localName = $element->{"LocalName"};
  print "end element $localName\n";
}

sub end_document
{
  my $self = shift;
  print "end document\n";
}

sub characters
{
  my ($self, $element) = @_;
}

package main;

use XML::SAX;

my $factory = XML::SAX::ParserFactory->new();
my $parser = $factory->parser( Handler => EADHandler->new() );

eval { $parser->parse_file($eadFile); };

print "Error parsing file: $@" if $@;

print "Done loading\n";
