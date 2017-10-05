#!/usr/bin/perl -w

package BoundaryConstants;

use constant BDRY_TYPE_ADVISORY_AREA			=>  1;
use constant BDRY_TYPE_ADIZ                     =>  2;
use constant BDRY_TYPE_ARTCC                    =>  3;
use constant BDRY_TYPE_AREA_CONTROL_CENTER      =>  4;
use constant BDRY_TYPE_BUFFER_ZONE              =>  5;
use constant BDRY_TYPE_CONTROL_AREA             =>  6;
use constant BDRY_TYPE_CONTROL_ZONE             =>  7;
use constant BDRY_TYPE_FIR                      =>  8;
use constant BDRY_TYPE_OCEAN_CONTROL_AREA       =>  9;
use constant BDRY_TYPE_RADAR_AREA               => 10;
use constant BDRY_TYPE_TCA                      => 11;
use constant BDRY_TYPE_UPPER_FLIGHT_INFO        => 12;
use constant BDRY_TYPE_MODE_C_DEFINED           => 13;
use constant BDRY_TYPE_OTHER                    => 14;
use constant BDRY_TYPE_ALERT                    => 32;
use constant BDRY_TYPE_DANGER                   => 33;
use constant BDRY_TYPE_MOA                      => 34;
use constant BDRY_TYPE_PROHIBITED               => 35;
use constant BDRY_TYPE_RESTRICTED               => 36;
use constant BDRY_TYPE_TEMPORARY                => 37;
use constant BDRY_TYPE_WARNING                  => 38;

use constant ALT_TYPE_AGL                       => 'A';
use constant ALT_TYPE_MSL                       => 'M';
use constant ALT_TYPE_FLIGHT_LEVEL              => 'F';
use constant ALT_TYPE_BY_NOTAM                  => 'N';

#use constant SEGMENT_TYPE_POINT                 => 'A';
#use constant SEGMENT_TYPE_GREAT_CIRCLE          => 'B';
#use constant SEGMENT_TYPE_CIRCLE                => 'C';
#use constant SEGMENT_TYPE_GENERALIZED           => 'G';
#use constant SEGMENT_TYPE_RHUMB_LINE            => 'H';
#use constant SEGMENT_TYPE_CCW_ARC               => 'L';
#use constant SEGMENT_TYPE_CW_ARC                => 'R';

use constant SEGMENT_TYPE_POINT                 =>  'P';
use constant SEGMENT_TYPE_LINE                  =>  'B';
use constant SEGMENT_TYPE_CCW_ARC               =>  'L';
use constant SEGMENT_TYPE_CW_ARC                =>  'R';
use constant SEGMENT_TYPE_CIRCLE                =>  'C';

1;
__END__
