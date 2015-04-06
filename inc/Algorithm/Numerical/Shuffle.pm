package Algorithm::Numerical::Shuffle;

use 5.006;

use strict;
use warnings;
no  warnings 'syntax';
use Exporter ();

our @ISA       = qw /Exporter/;
our @EXPORT    = qw //;
our @EXPORT_OK = qw /shuffle/;

our $VERSION   = '2009110301';

sub shuffle {
    return @_ if !@_ || ref $_ [0] eq 'ARRAY' && !@{$_ [0]};
    my $array = @_ == 1 && ref $_ [0] eq 'ARRAY' ? shift : [@_];
    for (my $i = @$array; -- $i;) {
        my $r = int rand ($i + 1);
       ($array -> [$i], $array -> [$r]) = ($array -> [$r], $array -> [$i]);
    }
    wantarray ? @$array : $array;
}


__END__

=head1 NAME

Algorithm::Numerical::Shuffle - Shuffle a list.

=head1 SYNOPSIS

    use Algorithm::Numerical::Shuffle qw /shuffle/;

    @shuffled = shuffle (1, 2, 3, 4, 5, 6, 7);

    $in_situ = [qw /one two three four five six/];
    shuffle $in_situ;

=head1 DESCRIPTION

C<shuffle> performs a one pass, fair shuffle on a list. If the list is
passed as a reference to an array, the shuffle is done in situ.

The subroutine returns the list in list context, and a reference to
the list in scalar context.

=head1 COMPLEXITY

The running time of the algorithm is linear in the size of the list.
For an in situ shuffle, the memory overhead is constant; otherwise,
linear extra memory is used.

=head1 LITERATURE

The algorithm used is discussed by Knuth [3]. It was first published
by Fisher and Yates [2], and later by Durstenfeld [1].

=head1 CAVEAT

Salfi [4] points to a big caveat. If the outcome of a random generator
is solely based on the value of the previous outcome, like a linear
congruential method, then the outcome of a shuffle depends on exactly
three things: the shuffling algorithm, the input and the seed of the
random generator. Hence, for a given list and a given algorithm, the
outcome of the shuffle is purely based on the seed. Many modern computers
have 32 bit random numbers, hence a 32 bit seed. Hence, there are at
most 2^32 possible shuffles of a list, foreach of the possible algorithms.
But for a list of n elements, there are n! possible permutations.
Which means that a shuffle of a list of 13 elements will not generate
certain permutations, as 13! > 2^32.

=head1 REFERENCES

=over

=item [1]

R. Durstenfeld: I<CACM>, B<7>, 1964. pp 420.

=item [2] 

R. A. Fisher and F. Yates: I<Statistical Tables>. London, 1938.
Example 12.

=item [3]

D. E. Knuth: I<The Art of Computer Programming>, Volume 2, Third edition.
Section 3.4.2, Algorithm P, pp 145. Reading: Addison-Wesley, 1997.
ISBN: 0-201-89684-2.

=item [4]

R. Salfi: I<COMPSTAT 1974>. Vienna: 1974, pp 28 - 35.

=back

=head1 SEE ALSO

C<< List::Util >> also has a C<< shuffle >> function which uses a similar
algorithm. But since it's written in C, it's much faster. For all practical
purposes, C<< List::Util >> supersedes this module. Unless you really need
in situ sorting.

=head1 DEVELOPMENT
 
The current sources of this module are found on github,
L<< git://github.com/Abigail/algorithm--numerical--shuffle.git >>.

=head1 AUTHOR

Abigail L<< mailto:cpan@abigail.be >>.

=head1 COPYRIGHT and LICENSE

Copyright (C) 1998 - 2000, 2009 by Abigail.

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:
     
The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHOR BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

=cut
