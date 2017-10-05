#!/usr/bin/perl -wT

package WPInfo;
@ISA = 'Exporter';
@EXPORT = qw(getUseDB getLoadDB);

use constant WP_DB_A    => wp_waypoints_a;
use constant WP_DB_B    => wp_waypoints_b;

my $current_use_db = WP_DB_B;
my $current_load_db = WP_DB_A;

sub getUseDB()
{
    return $current_use_db;
}

sub getLoadDB()
{
    return $current_load_db;
}

1;
__END__
