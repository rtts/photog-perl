package Photography::Website;
use strict;
use warnings;
use feature 'say';

use Photography::Website::Configure;
use DateTime;
use File::Copy            qw(copy);
use File::Path            qw(make_path remove_tree);
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
please refer to the photog(3) manpage for instructions and
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
    my $album = Photography::Website::Configure::configure($source, $parent) || return;

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

=back

=head2 Site Generation Functions

=over

=item B<generate>(I<$album>[, I<$parent>])

The second main entry point that generates the actual website images
and HTML files at the destinations specified inside the $album data
structure. The second parameter, $parent, is only used when called
recursively. Returns nothing.

=cut

sub generate {
    my $album = shift;
    my $parent = shift; # optional;
    my $refresh_index = 0;

    # Copy static files to destination root
    if (not $parent) {
        push @{$album->{protected}}, 'static';
        for (list(catfile(dist_dir('Photog'), 'static'))) {
            copy($_, $album->{destination}) or die "$_: $!";
        }
    }

    # Recursively update image files and album pages
    for my $item (@{$album->{items}}) {
        if ($item->{type} eq 'image') {
            update_image($item) and $refresh_index = 1;
        }
        elsif ($item->{type} eq 'album') {
            generate($item, $album) and $refresh_index = 1;
        }
    }

    if ($refresh_index) {
        return build_index($album, $parent);
    }
    else {
        return 0;
    }
}

=item B<update_image>(I<$img>[, I<$force>])

Given an $img node, checks if the image source is newer than the
destination. If needed, it builds new destination files. Returns
true if any images have been (re)generated.

=cut

sub update_image {
    my $img = shift;
    my $update_needed =
        not -f $img->{destination} or
        not -f $img->{thumbnail} or
        is_newer($img->{source}, $img->{destination});

    if ($update_needed) {
        build_image($img);
        return 1;
    }
    else {
        return 0;
    }
}

=item B<update_album>(I<$album>[, I<$parent>])

Given an $album node, first deletes any destination files that don't
have a corresponding source. Then it (re)builds the album's preview and index
if an update is needed. If a $parent is provided, it will be passed on
to the build_preview() function. Returns true if any changes have been
made at the destination directory.

=cut

sub update_album {
    my $album = shift;
    my $parent = shift; # optional
    my $update_needed =
        not -f $album->{index} or
        (not -f $album->{thumbnail} and not $album->{unlisted}) or
        is_newer($album->{config}, $album->{thumbnail});

    # Delete all destinations for which no source exists, unless they are protected
    for my $dest (list(@{$album->{destination}})) {
        if (not grep {$_->{destination} eq $dest} @{$album->{items}}) {
            if (not grep {basename($dest) eq $_} @{$album->{protected}}) {
                say ">>>>>>>>remove_tree($dest)";
                $update_needed = 1;
            }
        }
    }

    if ($update_needed) {
        build_preview($album, $parent) unless $album->{unlisted};
        build_index($album);
        return 1;
    }
    else {
        return 0;
    }
}

=item B<build_image>(I<$img>)

Builds the image's destination files, by shelling out to the the
watermark or scale and thumbnail commands.

=cut

sub build_image {
    my $img = shift;
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

=item B<build_index>(I<$album>)

Given an $album node, builds an album preview image and the album's
C<index.html> after sorting the album's images according to Exif
dates.

=cut

sub build_index {
    my $album = shift;

    # This defines a function named 'static' to be used in templates
    # to calculate relative pathnames (which ensure that the website
    # can be viewed by a browser locally)
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

    @{$album->{items}} = sort {
        return $a->{date} cmp $b->{date} if $album->{sort} eq 'ascending';
        return $b->{date} cmp $a->{date} if $album->{sort} eq 'descending';
    } @{$album->{items}};

    say $album->{url} . "index.html";
    $tt->process($album->{template}, $album, $album->{index})
        || die $tt->error();
}

=item B<create_preview>(I<$album>[, I<$parent>])

Creates an album preview image by making a random selection of the
album's images and calling the C<photog-preview> command. The optional
$parent argument is passed to the select_images() function (see
below).

=cut

sub build_preview {
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

photog(3)

=head1 AUTHOR

Photography::Website was written by Jaap Joris Vens <jj@rtts.eu>, and is
used to create his personal photography website at http://www.superformosa.nl/

=cut


1;
