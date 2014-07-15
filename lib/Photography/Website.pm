package Photography::Website;
use strict;
use warnings;
use constant false => 0;
use constant true  => 1;
use feature qw(say);
use File::Find;
use File::Basename;
use File::ShareDir qw(dist_dir);
use Image::Size;
use Cwd;
use Digest::MD5 qw(md5_hex);
use Image::ExifTool qw(:Public);
use Template; my $tt = Template->new({ABSOLUTE => 1});

our @artists;
our $copyright;
our $manipulate_exif;
our $pictures;
our $website;
our $watermark;
our @ignore;
our $thumbnail_size;
our $image_size;
our $verbose;
our $silent;
our $share         = dist_dir 'photography-website';
our $date_regex    = '[0-9]{4}-[0-9]{2}-[0-9]{2}';
our $private_regex = '(private)';
our $hidden_regex  = '(hidden)';

=head1 NAME

Photography::Website

=head1 SYNOPSIS

    use Photography::Website;

    my $conf = {

        # mandatory arguments
        Artist          => [ "Your Name", "Your Assistant's Name" ],
        Copyright       => "All Rights Reserved",
        Manipulate_EXIF => "true",
        Pictures        => "/home/username/Pictures",
        Website         => "/home/username/public_html",

        # optional arguments
        Watermark       => "/home/username/Pictures/watermark.png",
        Ignore          => [ "Lightroom Backups" ],
        Image_Size      => 2160,
        Verbose         => 1,
        Silent          => 0
    };

    Photography::Website::generate($conf);

=head1 DESCRIPTION

This Perl module generates a new or updates an existing photography
website. Please refer to the manual page of L<photog(3pm)|photog> for
documentation about the B<photog> command that provides a
user-friendly interface to use this module.

=head1 SEE ALSO

L<photog(3pm)|photog>

=head1 AUTHOR

Photography::Website was written by Jaap Joris Vens <jj@returntothesource.nl>, and
is used on his personal photography website http://www.superformosa.nl/

=cut

sub generate;
sub process;
sub create_gallery;
sub exif;
sub dirdate;
sub update_needed;
sub path;
sub is_image;
sub ignore;
sub title;
sub name;
sub parent;
sub dirlist;
sub thumbnail;
sub scale;
sub scale_and_watermark;

# This is the main function. Call it with reference to a configuration
# hash and it will make you a pretty photography website!
sub generate {
    my $config = shift or die;

    # Die if the following arguments aren't present
    if (ref $config->{Artist} eq ref []) {
        @artists = @{$config->{Artist}} or die;
    }
    else {
        $artists[0] = $config->{Artist} or die;
    }
    $copyright = $config->{Copyright} or die;
    $manipulate_exif = $config->{Manipulate_EXIF} or die;
    $manipulate_exif = $manipulate_exif =~ /true/i;
    $pictures = $config->{Pictures} or die;
    $website = $config->{Website} or die;

    # These arguments are optional
    $watermark = $config->{Watermark};
    if (ref $config->{Ignore} eq ref []) {
        @ignore = @{$config->{Ignore}};
    }
    else {
        $ignore[0] = $config->{Ignore};
    }
    $thumbnail_size = $config->{Thumbnail_Size} || 366; # undocumented
    $image_size = $config->{Image_Size} || 2160;
    $verbose = $config->{Verbose};
    $silent = $config->{Silent};

    # Setup the website directory
    `mkdir -p $website`;
    for (dirlist "$share/static") {
        `cp -n --no-preserve=mode $_ $website`;
    }
    `cp -n --no-preserve=mode $share/templates/index.template $website`;

    # Call &process for each item below pictures tree
    say "Scanning $pictures..." unless $silent;
    finddepth { wanted => sub { process $_ },
              no_chdir => 1}, $pictures;

    say "Website complete in $website" unless $silent;
}

# Entry point for (re)generating individual web resources. Pass a
# filename or directory and the corresponding resource on the website
# will be updated if needed.
sub process {
    my $original = shift or die;
    return if ignore $original;
    if (update_needed $original) {
        thumbnail $original;

        if (-f $original) {
            say "Processing image: $_" if $verbose;
            if ((parent $original) =~ /$private_regex/) {
                scale $original;
            }
            else {
                scale_and_watermark $original;
            }
        }

        elsif (-d $original) {
            say "Updating gallery for $original" unless $silent;
            my $webdir = $website . path $original;
            my $index = $webdir . 'index.html';
            `mkdir -p $webdir`;

            # Calculate the relative path to the root
            my $root = path $original;
            $root =~ s:[^/]+/:\.\./:g;
            $root =~ s:^/::;

            # Write the index.html
            my $context = {
                    website_title => "$artists[0] Photography",
                    root => sub { "$root$_[0]" },
                    items => (create_gallery $original)
                };
            $tt->process("$website/index.template", $context, $index) or die;
        }
    }
}

# Given an image directory, returns a reference to a list of hashes
# that represent gallery items, sorted by EXIF date
sub create_gallery {
    my $dir = shift or die;
    my @gallery;

    for my $original (dirlist $dir) {
        my $gallery_item = {};
        my $name = name $original;
        next if ignore $original;

        if (-f $original) {
            my $exifdata = exif $original;

            # Store image-specific info
            $gallery_item->{type}     = 'image';
            $gallery_item->{date}     = $exifdata->{date};
            $gallery_item->{settings} = $exifdata->{settings};
            $gallery_item->{src}      = "thumbnails/$name";
            $gallery_item->{href}     = $name;
        }
        elsif (-d $original) {
            next if ($name =~ /$private_regex/);
            next if ($name =~ /$hidden_regex/);

            # Store gallery-specific info
            $gallery_item->{type} = 'gallery';
            $gallery_item->{date} = dirdate $original;
            $gallery_item->{src}  = (title $name) . "/thumbnails/all.jpg";
            $gallery_item->{href} = (title $name) . '/';
        }

        my $absolute_src = $website . (path $dir) .  $gallery_item->{src};
        my ($width, $height) = imgsize $absolute_src;

        # Store remaining info
        $gallery_item->{width}  = $width;
        $gallery_item->{height} = $height;
        $gallery_item->{title}  = title $original;

        push @gallery, $gallery_item;
    }

    # Sort the list by EXIF date
    @gallery = sort {$b->{date} cmp $a->{date}} @gallery;

    return \@gallery;
}

# Returns some EXIF data of an image in a hash reference
sub exif {
    my $file = shift or die;
    my $data = {};
    my $exif = ImageInfo($file, 'MakerNote', 'Artist', 'Copyright', 'DateTimeOriginal', 'ExposureTime', 'FNumber', 'ISO');
    if (not %{$exif}) {
        die "EXIF info missing for $file, aborting...\n";
    }
    
    # If a raw file with the same name exists, copy over the EXIF data
    # to the file
    if ($manipulate_exif) {
        my $rawfile = $file;
        for my $ext ('dng', 'nef', 'cr2', 'crw') {
            $rawfile =~ s/\.jpg/\.$ext/;
            if (-f $rawfile) {
                say "Copying EXIF info from $rawfile to $file" if $verbose;
                # copy exif to jpeg
                last;
            }
        }
    }

    $data->{date} = $exif->{DateTimeOriginal} or 0;
    $data->{settings} = "$exif->{ExposureTime}, $exif->{FNumber}, ISO $exif->{ISO}";
    return $data;
}

# Extracts the date from a directory name in EXIF format
sub dirdate {
    my $dir = name shift or die;
    my $date;
    if ($dir =~ /($date_regex)/) {
        $date = $1;
        $date =~ s/-/:/g;
        $date .= " 00:00:00";
    }
    else {
        say "Directory $dir has no explicit date" if $verbose;
        # todo: Return the last modified date as a fallback
        $date = '0000:00:00 00:00:000';
    }
    return $date;
}

# Returns true is the corresponding web resource is in need of an update
sub update_needed {
    my $original = shift or die;
    my $original_time;
    my $derivative = $website . path $original;
    my $derivative_time;
    my $template_time = 0;

    if (-f $original) {
        $original_time = (stat $original)[9];
        $derivative_time = (stat $derivative)[9];
    }
    elsif (-d $original) {
        my $index = $derivative . 'index.html';
        my $latest = (`ls "$original" -t1`)[0]; # todo: don't fork
        chomp $latest;
        $original_time = (stat "$original/$latest")[9];
        $derivative_time = (stat $index)[9];
        $template_time = (stat "$website/index.template")[9];
    }

    unless ($derivative_time) {
        return true;
    }
    else {
        return ($original_time > $derivative_time) || ($template_time > $derivative_time);
    }
}

# Given an absolute path beneath the $pictures folder, returns the URL
# of the corresponding resource (which can be either an image or a
# gallery URL)
sub path {
    my $dir = shift or die;
    my $path = '/';
    
    # Loop over all parent dirs until $pictures
    for (split '/', substr "$dir", length $pictures) {
        next unless $_;

        # Keep image filenames intact
        if (is_image $_) {
            $path .= "$_";
        }

        # Substitute private dirs with secret URL
        elsif (/$private_regex/) {
            $path .= md5_hex("$_\n") . '/';
        }

        # Remove date and spaces from directory names
        else {
            s/$date_regex //;
            s/ .*//;
            $path .= "$_/";
        }
    }
    return $path;
}

sub is_image {
    return shift =~ /\.jpg$/;
}

# Returns true in the following circumstances:
# - the argument matches an entry from the @ignore list
# - the argument is a non-image file
# - the argument is a directory with less than 3 images
sub ignore {
    my $candidate = shift or die;
    if (grep {$candidate =~ /$_/} @ignore) {
        return true;
    }
    if (-f $candidate) {
        return not is_image $candidate;;
    }
    elsif (-d $candidate) {
        my @listing = dirlist $candidate;
        return scalar @listing <= 3;
    }
}

# Returns the display name of a file
sub title {
    my $file = name shift or die;
    $file =~ s/\.[^\.]+$//;
    $file =~ s/$date_regex //;
    return $file;
}

# Returns only the name of a file
sub name {
    my $file = shift or die;
    return (split m:/:, $file)[-1];
}

# Returns only the parent directory of a file
sub parent {
    my $file = shift or die;
    return (split m:/:, $file)[-2];
}

# Return a list of files in the directory
sub dirlist {
    my $dir = shift or die;
    $dir =~ s/\/$//;
    my @list;
    opendir my $dh, $dir or die;
    while (readdir $dh) {
        next if /^\./;
        push @list, "$dir/$_";
    }
    return @list;
}

sub thumbnail {
    my $original = shift or die;
    if (-d $original) {
        # create gallery thumbnail
    }
    elsif (-f $original) {
        # create image thumbnail
    }
}

sub scale {
    #todo
}

sub scale_and_watermark {
    #todo
}

1;
