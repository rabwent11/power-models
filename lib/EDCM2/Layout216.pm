﻿package EDCM2;

=head Copyright licence and disclaimer

Copyright 2015 Franck Latrémolière, Reckon LLP and others.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY AUTHORS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL AUTHORS OR CONTRIBUTORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

use warnings;
use strict;
use utf8;
use EDCM2::Layout;

sub otherLayout {
    my ( $model, @calculationOrder ) = @_;
    1 and $model->{layout} .= 'unnumbered';
    my $ordered = $model->orderedLayout( 1, @calculationOrder );
    [
        [
            'Param' => 'EDCM calculations',    # 'General parameters',
            undef, @{ $model->{generalTables} }
        ],
        [
            'GenSR' => 'EDCM calculations',    # 'Export super-red credits',
            undef, $ordered->[0]
        ],
        [
            'GenVol' => 'EDCM calculations',    # 'Export super-red credits',
            undef, $ordered->[1]
        ],
        [
            'GenAgg' => 'EDCM calculations',    # 'Export super-red credits',
            undef, $ordered->[2]
        ],
        [
            'GenCap' => 'EDCM calculations',    # 'Export capacity charges',
            undef, $ordered->[3]
        ],
        [
            'Fixed' => 'EDCM calculations', # 'Export and import fixed charges',
            undef, @$ordered[ 4 .. 8 ]
        ],
        [
            'Dem1' => 'EDCM calculations',    # 'Import charges before scaling',
            undef,
            $ordered->[9]
        ],
        [
            'DemAgg1' => 'EDCM calculations',  # 'Import charges after scaling',
            undef,
            $ordered->[10]
        ],
        [
            'Dem2' => 'EDCM calculations',    # 'Import charges before scaling',
            undef,
            $ordered->[11]
        ],
        [
            'DemAgg2' => 'EDCM calculations',  # 'Import charges after scaling',
            undef,
            $ordered->[12]
        ],
        [
            'Dem3' => 'EDCM calculations',     # 'Import charges after scaling',
            undef,
            @$ordered[ 13 .. $#$ordered ]
        ],
    ];
}

1;
