package Photography::Website;
use strict;
use warnings;
use feature 'say';

use DateTime;
use File::Copy            qw(copy);
use File::Path            qw(make_path);
use File::Basename        qw(basename dirname);
use File::ShareDir        qw(dist_file dist_dir);
use File::Spec::Functions qw(catfile);
use Image::Size           qw(imgsize);
use Image::ExifTool       qw(ImageInfo);
use Config::General       qw(ParseConfig);
use String::Random        qw(random_regex);
use Array::Utils          qw(array_minus);
use Algorithm::Numerical::Shuffle qw(shuffle);
use Template; my $tt = Template->new({ABSOLUTE => 1});

our $silent      = 0;
our $verbose     = 0;
my  $CONFIG_FILE = "photog.ini";

=head1 NAME

Photography::Website

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
photography website generator. If you're looking to generate websites,
please refer to the L<photog(3)> manpage for instructions and
configuration options. If you want to learn about the internals of
Photog!, read on.

A photography website is generated in two stages. The first stage
searches the source directory tree for images and optional
C<photog.ini> files, and processes them into a data structure of nested
albums. An album is simply a hash of configuration variables one of
which references a list of further hashes. This stage is kicked off by
the create_album() function.

The second stage loops through this data structure, compares all the
sources with their destinations, and (re)generates them if needed. It
builds a website with nested album pages than contain image thubmnails
and album preview thumbnails. The structure of album pages mirrors the
structure of the source image directory. This process is started with
the generate() function.

=head1 FUNCTIONS

The rest of this manpage is a description of the module's functions.
They are divided into three categories.  First, functions that process
the source files and directories.  Second, functions that generate the
website resources. Third, simple helper functions.

=head2 Source Processing Functions

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
    my $album = configure($source, $parent) || return;
    for (list($source)) {
        my $item;
        if (-f) {
            $item = create_img($_, $album) || next;
        }
        elsif (-d) {
            $item = create_album($_, $album) || next;
        }
        push @{$album->{items}}, $item;
    }
    return $album;
}

=item B<create_img>(I<$source>, I<$parent>)

Tries to create an image node of the file referred to by $source. Also
requires a $parent that references an album node. It returns a false
value if no image was created, or a reference to an image hash.

=cut

sub create_img {
    my $source = shift;
    my $parent = shift;
    return if not is_image($source);
    my $img = {};
    my $filename = basename($source);

    # Populate image hash
    $img->{type}   = 'image';
    $img->{name}   = strip_suffix($filename);
    $img->{url}    = $parent->{url} . $filename;
    $img->{href}   = $filename;
    $img->{src}    = "thumbnails/$filename";
    $img->{source} = $source;
    $img->{destination} = catfile($parent->{root}, $img->{url});
    $img->{thumbnail}   = catfile($parent->{destination}, $img->{src});
    $img->{watermark}   = $parent->{watermark};
    $img->{scale_command}     = $parent->{scale_command};
    $img->{watermark_command} = $parent->{watermark_command};
    $img->{thumbnail_command} = $parent->{thumbnail_command};
    return $img;
}

=item B<configure>(I<$source>[, I<$parent>])

Configures a new album in various ways. First, it tries to get the
configuration from a file named C<photog.ini> in the album's $source
directory. Second, it tries to copy the configuration variables from
the $parent album. Finally, it supplies default values. Returns a
reference to a new album, but one that doesn't have any child nodes
yet.

=cut

sub configure {
    my $source = shift;
    my $parent = shift; # optional
    my $album = get_config($source);

    # Special case for root albums
    $parent = $album if not $parent;

    # Implementation of the "oblivious" feature
    if (not $album) {
        return if $parent->{oblivious};
        $album = {};
    }

    # Implementation of the "private" feature
    if ($album->{private}) {
        $album->{slug} = random_regex('[1-9][a-hjkp-z2-9]{15}');
        $album->{unlisted} = "true";
        delete $album->{private};
        save_config($album, $source);
    }

    # Fixed parameters - These cannot be changed from a config file.
    $album->{type}   = 'album';
    $album->{source} = $source;
    $album->{config} = catfile($source, $CONFIG_FILE);
    $album->{name}   = basename($source);
    $album->{root}   = $parent->{root} || $parent->{destination} || die
        "ERROR: Destination not specified";

    # Special parameters - Either set in the config file or
    # calculated dynamically
    $album->{slug}
        ||= basename($source);
    $album->{url}
        ||= $parent->{url} ? "$parent->{url}$album->{slug}/": "/";
    $album->{href}
        ||= $album->{slug} . '/';
    $album->{src}
        ||= $album->{href} . "thumbnails/all.jpg";
    $album->{destination}
        ||= catfile($album->{root}, substr($album->{url}, 1));
    $album->{thumbnail}
        ||= catfile($album->{destination}, "thumbnails/all.jpg");
    $album->{index}
        ||= catfile($album->{destination}, "index.html");
    $album->{unlisted}
        ||= ($album == $parent);
    $album->{date}
        ||= DateTime->from_epoch(epoch => (stat $source)[9]);

    # Regular parameters - Set in the config file, propagated from
    # parent, or a default value.
    $album->{title}
        ||= $parent->{title}
        || "My Photography Website";
    $album->{copyright}
        ||= $parent->{copyright}
        || '';
    $album->{template}
        ||= $parent->{template}
        || dist_file('Photog', 'template.html');
    $album->{preview}
        ||= $parent->{preview}
        || 9;
    $album->{watermark}
        ||= $parent->{watermark}
        || '';
    $album->{sort}
        ||= $parent->{sort}
        || 'descending';
    $album->{fullscreen}
        ||= $parent->{fullscreen}
        || 1;
    $album->{oblivious}
        ||= $parent->{oblivious}
        || 0;
    $album->{scale_command}
        ||= $parent->{scale_command}
        || 'photog-scale';
    $album->{watermark_command}
        ||= $parent->{watermark_command}
        || 'photog-watermark';
    $album->{thumbnail_command}
        ||= $parent->{thumbnail_command}
        || 'photog-thumbnail';
    $album->{preview_command}
        ||= $parent->{preview_command}
        || 'photog-preview';

    return $album;
}

=back

=head2 Site Generation Functions

=over

=item B<generate>(I<$album>[, I<$parent>])

The second main entry point that generates the actual website images
and HTML files at the destinations specified inside the $album data
structure. The second parameter, $parent, is only used when called
recursively. It returns nothing.

=cut

sub generate {
    my $album = shift;
    my $parent = shift; # optional;
    my $update_needed = 0;

    # Copy static files to destination root
    if (not $parent) {
        for (list(catfile(dist_dir('Photog'), 'static'))) {
            copy($_, $album->{destination}) or die "$_: $!";
        }
    }

    # Recursively update image files and album pages
    for my $item (@{$album->{items}}) {
        if ($item->{type} eq 'image') {
            update_image($item);
        }
        elsif ($item->{type} eq 'album') {
            generate($item, $album);
        }
    }

    update_album($album, $parent);
}

=item B<update_image>(I<$img>)

Given an $img node, checks if the image source is newer than the
destination. If needed, it shells out to the the C<photog-watermark>
or C<photog-scale> command (depending on the configuration) to update
the website image. Then it calls C<photog-thumbnail> to update the
image thumbnail.

=cut

sub update_image {
    my $img = shift;
    return unless update_needed($img);

    say $img->{url} unless $silent;
    make_path(dirname($img->{destination}));
    if ($img->{watermark}) {
        system($img->{watermark_command},
               $img->{source},
               $img->{watermark},
               $img->{destination},
           );
    }
    else {
        system($img->{scale_command},
               $img->{source},
               $img->{destination},
           );
    }
    make_path(dirname($img->{thumbnail}));
    system($img->{thumbnail_command},
           $img->{source},
           $img->{thumbnail},
       );
}

=item B<update_album>(I<$album>)

Given an $album node, generates an album preview image and the album's
C<index.html> after sorting the album's images according to Exif
date. Like the update_image() function, it only operates if an update
is needed.

=cut

sub update_album {
    my $album = shift;
    my $parent = shift; # optional
    return unless update_needed($album);
    create_preview($album, $parent) unless $album->{unlisted};

    # Calculate the path to the static resources, relative
    # to the current page (relative pathnames ensure that
    # the website can be viewed by a browser locally)
    my $rel = $album->{url};
    $rel =~ s:[^/]+/:\.\./:g;
    $rel =~ s:^/::;
    $album->{static} = sub { "$rel$_[0]" };

    # Calculate and store image sizes and dates
    for (@{$album->{items}}) {
        ($_->{width}, $_->{height}) = imgsize($_->{thumbnail});
        if ($_->{type} eq 'image') {
            $_->{date} = exifdate($_->{source});
        }
    }

    if ($album->{sort} eq 'ascending') {
        @{$album->{items}} = sort {
            $a->{date} cmp $b->{date}
        } @{$album->{items}};
    }
    elsif ($album->{sort} eq 'descending') {
        @{$album->{items}} = sort {
            $b->{date} cmp $a->{date}
        } @{$album->{items}};
    }

    say $album->{url} . "index.html";
    $tt->process($album->{template}, $album, $album->{index})
        || die $tt->error();
}

=item B<update_needed>(I<$item>)

The argument $item can either be an album hash or an image hash. The
function returns true if the album/image's source is newer than the
destination, or if the destination doesn't exist. In case of albums,
it also returns true if the config file has changed. Otherwise it
returns false.

=cut

sub update_needed {
    my $item = shift;

    if ($item->{type} eq 'image') {
        if (not -f $item->{destination}) {
            return 1;
        }
        elsif (not -f $item->{thumbnail}) {
            return 1;
        }
        elsif (is_newer($item->{source}, $item->{destination})) {
            return 1;
        }
    }
    elsif ($item->{type} eq 'album') {
        if (not -f $item->{index}) {
            return 1;
        }
        elsif (not -f $item->{thumbnail} and not $item->{unlisted}) {
            return 1;
        }
        elsif (is_newer($item->{config}, $item->{index})) {
            return 1;
        }
        else {
            for (@{$item->{items}}) {
                if (is_newer($_->{thumbnail}, $item->{index})) {
                    return 1;
                }
            }
        }
    }
    return 0;
}

=item B<create_preview>(I<$album>[, I<$parent>])

Creates an album preview image by making a random selection of the
album's images and calling the C<photog-preview> command. The optional
$parent argument is passed to the select_images() function (see
below).

=cut

sub create_preview {
    my $album = shift;
    my $parent = shift; # optional

    my @images = select_images($album, $parent);
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

    make_path(dirname($album->{thumbnail}));
    system($album->{preview_command},
           @images,
           $album->{thumbnail},
       );
}

=item B<select_images>(I<$album>[, I<$parent>])

Returns a list of image paths that are eligible for inclusion in an
album preview. If an optional $parent is supplied, it makes sure that
the list only contains images whose filename does not appear in the
parent album. The reason for this is that the author of Photog! likes
to show the best photographs from an album on the front page, but not
also have those photographs included in an album preview.

=cut

sub select_images {
    my $album = shift;
    my $parent = shift; # optional
    if ($parent) {

        # Read the following lines from end to beginning
        my %excl = map {$_ => 1}
            map {$_->{href}}
            grep {$_->{type} eq 'image'}
            @{$parent->{items}};

        return map {$_->{thumbnail}}
            grep {not $excl{$_->{href}}}
            grep { $_->{type} eq 'image' }
            @{$album->{items}};
    }
    else {
        return map {$_->{thumbnail}} @{$album->{items}};
    }
}

=back

=head2 Helper Functions

=over

=item B<get_config>(I<$directory>)

Tries to find and parse $directory/photog.ini into a configuration
hash and returns a reference to it. Returns false if no photog.ini was
found.

=cut

sub get_config {
    my $directory = shift;
    my $file = catfile($directory, $CONFIG_FILE);
    if (-f $file) {
        return { ParseConfig(-ConfigFile=>$file, -AutoTrue=>1) };
    }
    return 0;
}

=item B<save_config>(I<$config>, I<$directory>)

The other way around, saves the $config hash reference to the file
photog.ini inside the $directory. Returns nothing.

=cut

sub save_config {
    my $config = shift;
    my $directory = shift;
    my $file = catfile($directory ,$CONFIG_FILE);
    open(my $fh, '>', $file)
        or die "ERROR: Can't open '$file' for writing\n";
    for my $key (keys %{$config}) {
        say $fh "$key = $config->{$key}";
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
    opendir(my $dh, $dir) or die
        "ERROR: Cannot read contents of directory '$dir'\n";
    while (readdir $dh) {
        next if /^\./;
        push @files, "$dir/$_" if -f "$dir/$_";
        push @dirs, "$dir/$_" if -d "$dir/$_";
    }
    sub alphabetical { lc($a) cmp lc($b) }
    @files = sort alphabetical @files;
    @dirs = sort alphabetical @dirs;
    return @dirs, @files;
}

=item B<is_image>(I<$filename>)

Returns true if the filename ends with C<.jpg>.

=cut

sub is_image {
    return shift =~ /\.jpg$/;
}

=item B<strip_suffix>(I<$filename>)

Removes all characters after the last dot of $filename, and the dot
itself.

=cut

sub strip_suffix {
    my $file = shift;
    $file =~ s/\.[^\.]+$//;
    return $file;
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

L<photog(3pm)|photog>

=head1 AUTHOR

Photography::Website was written by Jaap Joris Vens <jj@rtts.eu>, and is
used to create his personal photography website at http://www.superformosa.nl/

=cut


1;
