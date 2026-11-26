#!/usr/bin/env perl
# Copyright (c) 2026 Akita Engineering
# SPDX-License-Identifier: GPL-3.0-only
use strict;
use warnings;
use JSON::PP qw(decode_json);

my $path = shift @ARGV;
exit 1 unless defined $path && open my $archive, '<:raw', $path;

# The outer pickle stores the size of the header pickle. File offsets in
# the header are relative to the payload that follows both pickles.
read($archive, my $prefix, 16) == 16 or exit 1;
my ($outer_size, $header_size, $padded_size, $json_size) = unpack 'V4', $prefix;
exit 1 unless $outer_size == 4 && $header_size == $padded_size + 4
    && $json_size <= $header_size - 8 && $header_size <= 64 * 1024 * 1024;
read($archive, my $header, $json_size) == $json_size or exit 1;

my $package = eval { decode_json($header)->{files}{'package.json'} };
exit 1 unless ref($package) eq 'HASH' && ($package->{offset} // '') =~ /\A[0-9]+\z/
    && ($package->{size} // '') =~ /\A[0-9]+\z/ && $package->{size} <= 1024 * 1024;
seek($archive, 8 + $header_size + $package->{offset}, 0) or exit 1;
read($archive, my $contents, $package->{size}) == $package->{size} or exit 1;

my $version = eval { decode_json($contents)->{version} };
exit 1 unless defined($version) && $version =~ /\A[0-9]+(?:\.[0-9]+)+\z/;
print "$version\n";
