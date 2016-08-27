﻿package SpreadsheetModel::CLI::CommandRunner;

=head Copyright licence and disclaimer

Copyright 2011-2016 Franck Latrémolière and others. All rights reserved.

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

use SpreadsheetModel::CLI::DataTools;
use SpreadsheetModel::CLI::MakeModels;
use SpreadsheetModel::CLI::ParseSpreadsheet;
use SpreadsheetModel::CLI::Sampler;
use SpreadsheetModel::CLI::UseDatabase;
use SpreadsheetModel::CLI::YamlTools;

use Encode qw(decode_utf8);
use File::Spec::Functions qw(abs2rel catdir catfile rel2abs);
use File::Basename 'dirname';

use constant {
    C_HOMEDIR       => 0,
    C_VALIDATEDLIBS => 1,
    C_DESTINATION   => 2,
    C_LOG           => 3,
};

sub new {
    my $class = shift;
    bless [@_], $class;
}

sub finish {
    my ($self) = @_;
    $self->makeFolder;
}

sub log {
    my ( $self, $verb, @objects ) = @_;
    warn "$verb: @objects\n";
    return if $verb eq 'makeFolder';
    push @{ $self->[C_LOG] },
      join( "\n", $verb, map { "\t$_"; } @objects ) . "\n\n";
}

sub makeFolder {
    my ( $self, $folder ) = @_;
    if ( $self->[C_DESTINATION] )
    {    # Close out previous folder $self->[C_DESTINATION]
        return if $folder && $folder eq $self->[C_DESTINATION];
        if ( $self->[C_LOG] ) {
            open my $h, '>', '~$tmptxt' . $$;
            print {$h} @{ $self->[C_LOG] };
            close $h;
            local $_ = "$self->[C_DESTINATION].txt";
            s/^_+([^\.])/$1/s;
            rename '~$tmptxt' . $$, $_;
            delete $self->[C_LOG];
        }
        chdir '..';
        my $tmp = '~$tmp-' . $$ . ' ' . $self->[C_DESTINATION];
        return if rmdir $tmp;
        rename $self->[C_DESTINATION], $tmp . '/~$old-' . $$
          if -e $self->[C_DESTINATION];
        rename $tmp, $self->[C_DESTINATION];
        system 'open', $self->[C_DESTINATION] if -d '/System/Library';   # macOS
        delete $self->[C_DESTINATION];
    }
    if ($folder) {    # Create temporary folder
        if ( -d '/System/Library' )
        {             # Try to use a temporary memory disk on macOS
            my $ramDiskBlocks = 12_000_000;    # About 6G, in 512-byte blocks.
            my $ramDiskName       = 'Temporary volume (power-models)';
            my $ramDiskMountPoint = "/Volumes/$ramDiskName";
            unless ( -d $ramDiskMountPoint ) {
                my $device = `hdiutil attach -nomount ram://$ramDiskBlocks`;
                $device =~ s/\s*$//s;
                system qw(diskutil erasevolume HFS+), $ramDiskName, $device;
            }
            chdir $ramDiskMountPoint if -d $ramDiskMountPoint && -w _;
        }
        my $tmp = '~$tmp-' . $$ . ' ' . ( $self->[C_DESTINATION] = $folder );
        mkdir $tmp;
        chdir $tmp;
    }
}

sub R {
    my ( $self, @commands ) = @_;
    open my $r, '| R --vanilla --slave';
    binmode $r, ':utf8';
    require SpreadsheetModel::Data::RCode;
    print {$r} SpreadsheetModel::Data::RCode->rCode(@commands);
}

our $AUTOLOAD;

sub comment { }

sub DESTROY { }

sub AUTOLOAD {
    no strict 'refs';
    warn "$AUTOLOAD not implemented";
    *{$AUTOLOAD} = sub { };
    return;
}

package NOOP_CLASS;
our $AUTOLOAD;

sub AUTOLOAD {
    no strict 'refs';
    *{$AUTOLOAD} = sub { };
    return;
}

1;
