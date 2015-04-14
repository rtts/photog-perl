my $DIST = 'Photography-Website';
package Photography::Website;
$Photography::Website::VERSION = '0.26';
use strict;
use warnings;
use feature 'say';

use Photography::Website::Configure;
use DateTime;
use File::Path            qw(make_path remove_tree);
use File::Basename        qw(basename dirname);
use File::ShareDir        qw(dist_dir);
use File::Spec::Functions qw(catfile catdir);
use File::Copy::Recursive qw(dircopy);
use Image::Size           qw(imgsize);
use Image::ExifTool       qw(ImageInfo);
use String::Random        qw(random_regex);
use Algorithm::Numerical::Shuffle qw(shuffle);
use Template; my $tt = Template->new({ABSOLUTE => 1});

our $silent  = 0;
our $verbose = 0;

=head1 NAME

Photography::Website - Photography Website Generator

=head1 SYNOPSIS

    use Photography::Website;

    my $source      = "$ENV{HOME}/Pictures";
    my $destination = "$ENV{HOME}/public_html";

    # Process the pictures tree
    my $website = Photography::Website::create_album($source);

    # Generate the website
    Photography::Website::generate($website);

=head1 DESCRIPTION

The Photography::Website module contains the core of the Photog!
photography website generator. Please refer to L<photog> for a more
general introduction on how to run Photog! and how to configure
it. All of the configuration options are documented in
L<Photography::Website::Configure>. If you want to learn about the
internals of Photog!, read on.

A photography website is generated in two stages. The first stage
searches the source directory tree for images and optional
C<photog.ini> files, and processes them into a data structure of
nested albums. An album is simply a hash of configuration variables
one of which ($album->{items}) references a list of further
hashes. This stage is kicked off by the create_album() function.

The second stage loops through this data structure, compares all the
sources with their destinations, and (re)generates them if needed. It
builds a website with nested album pages that contain image thubmnails
and album preview thumbnails. The structure of album pages mirrors the
structure of the source image directory. This process is started with
the generate() function.

=head1 FUNCTIONS

=over

=item B<create_album>(I<$source>[, I<$parent>])

The main entry point for creating a website structure. $source should
be a directory name, $parent is only used when this function is called
recursively. Returns an album with nested sub-albums that represents
the source directory tree.

=cut

sub create_album {
    my $source = shift;
    my $parent = shift; # optional
    my $album  = Photography::Website::Configure::album($source, $parent) || return;

    for (list($source)) {
        my $item;
        if (-f) {
            $item = Photography::Website::Configure::image($_, $album) || next;
            say "  Found image: $_" if $verbose;
        }
        elsif (-d) {
            $item = create_album($_, $album) || next;
        }
        $album->{allfiles}->{$item->{destination}} = 1;
        $album->{allfiles}->{$item->{thumbnail}} = 1;
        push @{$album->{items}}, $item;
    }
    return $album;
}

=item B<generate>(I<$album>)

The second main entry point that generates the actual website images
and HTML files at the destinations specified inside the $album data
structure. Returns true if the index of $album has been regenerated.

=cut

sub generate {
    my $album    = shift;
    my $outdated = 0;

    # Copy static files to destination root
    if (not $album->{parent}) {
        push @{$album->{protected}}, 'static';
        my $static_source = catdir(dist_dir($DIST), 'static');
        my $static_destination = catdir($album->{destination}, 'static');
        dircopy($static_source, $static_destination) and say "  /static/" unless $silent;
    }

    # Recursively update image files and album pages
    for my $item (@{$album->{items}}) {
        if ($item->{type} eq 'image') {
            if (update_image($item)) {
                $outdated = 1;
            }
        }
        elsif ($item->{type} eq 'album') {
            if (generate($item, $album) and not $item->{unlisted}) {
                $outdated = 1;
            }
        }
    }

    return update_album($album, $outdated);
}

=item B<update_image>(I<$image>[, I<$force>])

Given an $image node, checks if the image source is newer than the
destination. If needed, or if $force is true, it builds new
destination files. Returns true if any images have been (re)generated.

=cut

sub update_image {
    my $img           = shift;
    my $update_needed = shift || (
        not -f $img->{destination} or
        not -f $img->{thumbnail} or
        is_newer($img->{source}, $img->{destination})
    );

    if ($update_needed) {
        build_image($img);
        return 1;
    }
    else {
        say "  No update needed for $img->{source}" if $verbose;
        return 0;
    }
}

=item B<update_album>(I<$album>[, I<$force>])

Given an $album node, first deletes any destination files that don't
have a corresponding source. Then it (re)builds the album's preview
and index if an update is needed or if $force is true. Returns true
if any changes have been made at the destination directory.

=cut

sub update_album {
    my $album         = shift;
    my $update_needed = shift || ( # optional
        not -f $album->{index} or
        (not -f $album->{thumbnail} and not $album->{unlisted}) or
        is_newer($album->{config}, $album->{index})
    );

    if (not -d $album->{destination}) {
        make_path($album->{destination});
    }

    # Delete all destinations that do not appear in the allfiles hash, unless they are protected
    for my $dest (list($album->{destination}), list(catdir($album->{destination}, 'thumbnails'))) {
        my $file = basename($dest);
        if (not exists $album->{allfiles}->{$dest}) {
            if (not grep {$_ eq $file} @{$album->{protected}}) {
                say "  Removing $dest" unless $silent;
                remove_tree($dest);
                $update_needed = 1;
            }
        }
    }

    if ($update_needed) {
        build_preview($album) unless $album->{unlisted};
        build_index($album);
    }
    else {
        say "  Not regenerating $album->{index}" if $verbose;
    }

    return $update_needed;
}

=item B<build_image>(I<$image>)

Builds the image's destination files, by shelling out to the the
watermark or scale and thumbnail commands.

=cut

sub build_image {
    my $img = shift;
    say "  $img->{url}" unless $silent;
    make_path(dirname($img->{destination}));
    if ($img->{watermark}) {
        system($img->{watermark_command},
               $img->{source},
               $img->{watermark},
               $img->{destination},
           ) and die "ERROR: Watermark command failed\n";
    }
    else {
        system($img->{scale_command},
               $img->{source},
               $img->{destination},
           ) and die "ERROR: Scale command failed\n";
    }
    make_path(dirname($img->{thumbnail}));
    system($img->{thumbnail_command},
           $img->{source},
           $img->{thumbnail},
       ) and die "ERROR: Thumbnail command failed\n";
}

=item B<build_index>(I<$album>)

Given an $album node, builds an album preview image and the album's
C<index.html> after sorting the album's images according to Exif
dates.

=cut

sub build_index {
    my $album = shift;

    # This defines a function named 'root' to be used in templates to
    # calculate the relative pathname to the website root (which
    # ensures that the website can be viewed by a browser locally)
    my $rel = $album->{url};
    $rel =~ s:[^/]+/:\.\./:g;
    $rel =~ s:^/::;
    $album->{root} = sub { $rel.$_[0] };

    # Calculate and store image sizes and dates
    for (@{$album->{items}}) {
        ($_->{width}, $_->{height}) = imgsize($_->{thumbnail});
        if ($_->{type} eq 'image') {
            $_->{date} = exifdate($_->{source});
        }
    }

    @{$album->{items}} = sort {
        return $a->{date} cmp $b->{date} if $album->{sort} eq 'ascending';
        return $b->{date} cmp $a->{date} if $album->{sort} eq 'descending';
    } @{$album->{items}};

    if (not -f $album->{thumbnail}) {
        $album->{unlisted} = 1;
    }

    say "  $album->{url}index.html" unless $silent;
    $tt->process($album->{template}, $album, $album->{index})
        || die $tt->error();
}

=item B<create_preview>(I<$album>)

Creates an album preview image by making a random selection of the
album's images and calling the C<photog-preview> command.

=cut

sub build_preview {
    my $album  = shift;

    my @images = select_images($album);
    my $size = scalar @images;
    if ($size < 3) {
        say "WARNING: Not enough images available in '$album->{name}' to create a preview";
        return;
    }
    elsif ($size < $album->{preview}) {
        say "WARNING: Only $size preview images available for '$album->{name}' ($album->{preview} requested)" unless $silent;
        $album->{preview} = $size;
    }

    # Round the number of preview images down to 3, 6, or 9
    $album->{preview}-- until grep {$_ == $album->{preview}} (3, 6, 9);

    # Shuffle the list and pick N preview images
    @images = @{[shuffle @images]}[0..($album->{preview})-1];

    say "  Creating preview of $album->{preview} images for '$album->{name}'..." if $verbose;
    make_path(dirname($album->{thumbnail}));
    system($album->{preview_command},
           @images,
           $album->{thumbnail},
       ) and die "ERROR: Preview command failed\n";
}

=item B<select_images>(I<$album>)

Returns a list of image paths that are eligible for inclusion in an
album preview. It makes sure that the list only contains images whose
filename does not appear in the parent album. The reason for this is
that the author of Photog! likes to show the best photographs from an
album on the front page, but not also have those photographs included
in an album preview.

=cut

sub select_images {
    my $album  = shift;
    if ($album->{parent}) {

        # Read the following lines from end to beginning
        my %excl = map {$_ => 1}
            map {$_->{href}}
            grep {$_->{type} eq 'image'}
            @{$album->{parent}->{items}};

        return map {$_->{thumbnail}}
            grep {not $excl{$_->{href}}}
            grep { $_->{type} eq 'image' }
            @{$album->{items}};
    }
    else {
        return map {$_->{thumbnail}} @{$album->{items}};
    }
}

=item B<list>(I<$dir>)

Returns a list of absolute pathnames to all the files and directories
inside $dir.

=cut

sub list {
    my $dir = shift;
    my @files;
    my @dirs;
    opendir(my $dh, $dir) or return ();
    while (readdir $dh) {
        next if /^\./;
        push @files, catfile($dir, $_) if -f catfile($dir,$_);
        push @dirs, catdir($dir, $_) if -d catdir($dir, $_);
    }
    sub alphabetical { lc($a) cmp lc($b) }
    @files = sort alphabetical @files;
    @dirs = sort alphabetical @dirs;
    return @dirs, @files;
}

=item B<is_newer>(I<$file1>, I<$file2>)

Determines the modification times of $file1 and $file2 (which should
pathnames). It both files exist and $file1 is newer than $file2, it
returns true. Beware: if both files are of the same age, $file1 is not
newer than $file2.

=cut

sub is_newer {
    my $file1 = shift;
    my $file2 = shift;
    return unless -f $file1 and -f $file2;
    my $time1 = (stat $file1)[9];
    my $time2 = (stat $file2)[9];
    return $time1 > $time2;
}

=item B<exifdate>(I<$file>)

Extracts the value of the Exif tag C<DateTimeOriginal> from the
provided image path, converts it to ISO 8601 format, and returns
it. Prints a warning and returns 0 if the Exif tag could not be found.

=cut

sub exifdate {
    my $file = shift or die;
    my $exif = ImageInfo($file, 'DateTimeOriginal');
    if (not $exif->{DateTimeOriginal}) {
        say "WARNING: Exif tag 'DateTimeOriginal' missing from '$file'";
        return 0;
    }
    my ($date, $time) = split(/ /, $exif->{DateTimeOriginal});
    $date =~ s/:/-/g;
    return $date . 'T' . $time;
}

=back

=head1 SEE ALSO

L<photog>, L<Photography::Website::Configure>

=head1 AUTHOR

Photog! was written by Jaap Joris Vens <jj@rtts.eu>, and is used to
create his personal photography website at L<http://www.superformosa.nl/>

=cut

1;
