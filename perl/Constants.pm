#!/usr/bin/perl -wT

package Constants;

# Don't really need this in a varialbe somewhere, just need to get it
# codified somewhere
my %chart_flags = 
    {
        1   =>  "High Altitude",
        2   =>  "Low Altitude",
        4   =>  "RNAV",
        8   =>  "Terminal"
    };

1;
__END__
