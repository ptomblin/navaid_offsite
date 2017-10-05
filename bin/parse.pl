#!/usr/bin/perl -w

use constant TIMEOUT => 2;
$SIG{ALRM} = sub {die "timeout"};

my %count_ips_per_page = ();
my %count_pages_per_ip = ();
my %count_referrer = ();

while (<>) {
#    next if /\.(gif|class|png) /i;
#    next if /_thumb\.jpg /;
#    next if /206\.27\.96\.47/;

    my ($site, $ip, $day, $month, $page, $referrer) =
        m#^(.+) (.+) - [^ ]+ \[([^/]+)/([^/]+).*[gGpPHh][EeoO][aAsS]*[dDtT] ([^ ]+) [^"]*" [^"]*"([^"]*)".*#;

    if (defined $ip && $ip ne "" )
    {
        next if ($ip =~ /192\.168\.1\./);
        next if ($ip =~ /216\.42\.79\.47/);

        $page =~ s/%7[Ee]/~/;
        $page =~ s/index.html//;

        if (!exists $count_ips_per_page{$page})
        {
            $count_ips_per_page{$page} = ();
        }
        if (!exists $count_ips_per_page{$page}->{$ip})
        {
            $count_ips_per_page{$page}->{$ip} = 0;
        }
        $count_ips_per_page{$page}->{$ip}++;

        if (!exists $count_pages_per_ip{$ip})
        {
            $count_pages_per_ip{$ip} = ();
        }
        if (!exists $count_pages_per_ip{$ip}->{$page})
        {
            $count_pages_per_ip{$ip}->{$page} = 0;
        }
        $count_pages_per_ip{$ip}->{$page}++;
    }
    next if !defined $referrer;
    next if $referrer eq "-";
    next if $referrer =~ /(xcski|navaid).(com|net)/;
    if (!exists $count_referrer{$referrer})
    {
        $count_referrer{$referrer} = 0;
    }
    $count_referrer{$referrer}++;

}
dump_all_caches();

sub dump_all_caches
{
    my ($page, %IP, $ip, $hitcount);

    print "per page:\n";
    foreach $page (sort keys %count_ips_per_page)
    {
        $IP = $count_ips_per_page{$page};
        print "\npage: $page\n";

#        while (($ip, $hitcount) = each %$IP)
        foreach $ip (sort keys %$IP)
        {
            $hitcount = $$IP{$ip};
            my $name = lookup($ip);
            print "$hitcount hits from $name ($ip)\n";
        }
    }
    %count_ips_per_page = ();

    print "\nper ip:\n";
    foreach $ip (sort keys %count_pages_per_ip)
    {
        $PAGES = $count_pages_per_ip{$ip};
        my $name = lookup($ip);
        print "\nFrom: $name ($ip)\n";

#        while (($page, $hitcount) = each %$PAGES)
        foreach $page (sort keys %$PAGES)
        {
            $hitcount = $$PAGES{$page};
            print "$hitcount hits for $page\n";
        }
    }
    %count_pages_per_ip = ();

    print "\nreferrers:\n";
    while (($referrer, $hitcount) = each %count_referrer)
    {
        print "$hitcount hits from $referrer\n";
    }
    %count_referrer = ();
}

sub lookup {
  my $ip = shift;
  return $ip unless $ip=~/\d+\.\d+\.\d+\.\d+/;
  unless (exists $CACHE{$ip}) {
    my @h = eval <<'END';
    alarm(TIMEOUT);
    my @i = gethostbyaddr(pack('C4',split('\.',$ip)),2);
    alarm(0);
    @i;
END
    $CACHE{$ip} = $h[0] || undef;
  }
  return $CACHE{$ip} || $ip;
}
