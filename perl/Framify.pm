#!/usr/bin/perl -w
#File Framify.pm
#
#	This file takes the passed in url for a web page that was designed to
#	be in a frame, and builds a non-frame version with a title and footer
#	on it.
#	The real files actually live in $REAL_LOCATION (and are accessible via
#	$REAL_URLS.
#
#	Improvements needed:
#		- special handling for index.html
#		- read everything from configuration files
#       - use the "real" header instead of the title header.
#       - handle non-HTML files

package Framify;

use strict;
use Apache::Constants qw(:common);
use Apache::File();
use Apache::URI();


my %BARS = ();

my $TABLEATTS		= 'WIDTH="100%" BORDER=1';
my $TABLECOLOUR		= '#C8FFFF';
my $ACTIVECOLOUR	= '#FF0000';

#	Most of this stuff should probably move into a configuration file or
#	PerlSetEnvs in the apache config.  Sue me.
my $REAL_URLS		= "/rfc/frames/";
my $REAL_LOCATION	= "/home/ptomblin/webs/rochesterflyingclub.com/htdocs/frames";

my $TITLE			= "title.html";
my $NAV_BOTTOM		= "nav_bottom.html";


my $titlefile	= $REAL_LOCATION . "/" . $TITLE;
my $navfile		= $REAL_LOCATION . "/" . $NAV_BOTTOM;

open(DEBUG,">>/tmp/framify.out");
#open(DEBUG,">/tmp/framify.out");
my $ofh = select(DEBUG); $| = 1; select $ofh;

local($/) = "";
my $fh = Apache::File->new($titlefile);
#	read the whole title file into a string
my $titlestring = <$fh>;

#	strip out everything after the body
$titlestring =~ s#.*<BODY[^>]*>(.*)</BODY>.*#$1#ims;

$fh->close();

$fh = Apache::File->new($navfile);
my $navstring = <$fh>;

#	strip out everything before the body
$navstring =~ s#.*<BODY[^>]*>(.*)</BODY>.*#$1#ims;

$fh->close();

print DEBUG "handler v6 is loaded\n";

sub handler
{
	my $r = shift;
#	$r->content_type eq 'text/html'		|| return DECLINED;

	my $parsed_uri = $r->parsed_uri;
print DEBUG "handler v6 , called parsed_uri = ".$parsed_uri->path()."\n";

	my $real = $parsed_uri->path();
	$real =~ s?.*/??;

	#my ($nothing, $real) = split("/", $parsed_uri->path_info());
#    print DEBUG "real = $real\n";

	my $realfile	= $REAL_LOCATION . "/" . $real;
#    print DEBUG "realfile = $realfile\n";

	return DECLINED unless -e $titlefile;
#    print DEBUG "titlefile exists\n";
	return DECLINED unless -e $realfile;
#    print DEBUG "realfile exists\n";
	return DECLINED unless -e $navfile;
#    print DEBUG "files all exist\n";

	local($/) = "";
	my $fh = Apache::File->new($realfile);

	#	There are no more checks I can do at this point.
    $r->content_type("text/html");
	$r->send_http_header;
	return OK if $r->header_only;

    my $localNavString = $navstring;
    $localNavString =~ s#<a\s*href="$real"\s*>([^<]*)</a>#$1#sig;
#    print DEBUG "navString changed to $localNavString\n";

    while (<$fh>)
    {
        s:(</BODY>):<HR>\n$localNavString$1:i;
        s:(<BODY[^>]*>):$1$titlestring<HR>\n:si;
    } continue
    {
        $r->print($_);
    }
    $fh->close();

	return OK;
}

1;
__END__

