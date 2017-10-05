#!/usr/bin/perl -w

package Datasources;

use constant DATASOURCE_FAA			=> 1;
use constant DATASOURCE_DAFIF		=> 2;
use constant DATASOURCE_WPNL		=> 3;
use constant DATASOURCE_FR			=> 4;
use constant DATASOURCE_GR			=> 5;
use constant DATASOURCE_AUS			=> 6;
use constant DATASOURCE_ON			=> 7; # Stephan V's Ontario
use constant DATASOURCE_FR_GD		=> 8; # Georges Delamare's France
use constant DATASOURCE_CA_VT		=> 9; # Vic Thompson's Canada
use constant DATASOURCE_AU_CP		=> 10; # Christian Plonka Austria
use constant DATASOURCE_NL_HV		=> 11; # Hans Vogelaar Netherlands
use constant DATASOURCE_SG_GP		=> 12; # Stan Gosnell Gulf Platforms
use constant DATASOURCE_MA_FC		=> 13; # Malaysia and Singapore
use constant DATASOURCE_AUS_PR		=> 14; # Philip Roberts Australia
use constant DATASOURCE_CH_MR		=> 15; # Michel Rueedi Switzerland
use constant DATASOURCE_UK_DC		=> 16; # Dave Crispin UK
use constant DATASOURCE_BC_CE		=> 17; # Craig J. Elder British Columbia
use constant DATASOURCE_BR_FB		=> 18; # Brazil Airports, Fabrica Bolorino
use constant DATASOURCE_EI_AM		=> 19; # Ireland, Andrew J. Mackriell
use constant DATASOURCE_CA_DR		=> 20; # Western Canada, Douglas Robertson
use constant DATASOURCE_UK_NJ		=> 21; # UK, Nadim Janjua
use constant DATASOURCE_AR_OO		=> 22; # Argentina, Osvaldo Oritz
use constant DATASOURCE_CA_MC		=> 23; # McCormick
use constant DATASOURCE_CA_GP		=> 24; # George Plews
use constant DATASOURCE_WO_DR		=> 25; # Demaf Rame
use constant DATASOURCE_WO_OA		=> 26; # Our Airports
use constant DATASOURCE_AS_BS		=> 27; # Bas Scheffers, Australia VFR_WP
use constant DATASOURCE_CA_BC		=> 28; # Blake Crosby's VFR_WP
use constant DATASOURCE_EAD			=> 30; # Eurocontrol
use constant DATASOURCE_HANGAR		=> 31; # TheHangar.co.uk

use constant DATASOURCE_COMBINED_OFFICIAL => 98; # Combined FAA and DAFIF
use constant DATASOURCE_COMBINED_USER	  => 99; # Combined all user data

1;
__END__
