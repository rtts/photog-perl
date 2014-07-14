package Photography::Website;
use strict;
use warnings;
use constant false => 0;
use constant true  => 1;
use feature qw(say);
use File::Find;
use File::Basename;
use Image::Size;
use Cwd;
use Digest::MD5 qw(md5_hex);
use Image::ExifTool qw(:Public);
use Template; my $tt = Template->new({ABSOLUTE => 1});

our @artists = (
    {
        artist => 'Jaap Joris Vens - www.superformosa.nl',
        copyright => 'http://creativecommons.org/licenses/by-sa/4.0/'
    },
    {
        artist => 'Jolanda Verhoef - www.superformosa.nl',
        copyright => 'http://creativecommons.org/licenses/by-sa/4.0/'
    }
);

our @ignore        = ('Lightroom Backups');
our $pictures      = "$ENV{'HOME'}/Pictures";
our $watermark     = "$pictures/watermark.png";
our $website       = cwd . "/photography";

my $script_dir = "AAAARGH HOW CAN I EEVVER";

our $template_file = "$script_dir/index.template";
our $static        = "$script_dir/static";

our $date_regex    = '[0-9]{4}-[0-9]{2}-[0-9]{2}';
our $private_regex = '(private)';
our $hidden_regex  = '(hidden)';

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
sub thumbnail;
sub scale;
sub scale_and_watermark;

# This is the main function. Call it with reference to a configuration
# hash and it will make you a pretty photography website!
sub generate {
    # my $config = shift;
    # $artist = $config->{Website} or die;
    # $manipulate_exif = $config->{Manipulate_EXIF} or die;
    # $copyright = $config->{Copyright} or die;
    # $pictures = $config->{Pictures} or die;
    # $watermark = $config->{Watermark} or die;
    # $website = $config->{Website} or die;
    $| = 1;

    say "YES! Photography::Website is successfully installed!";
    return;

    # Setup the website directory
    `mkdir -p $website`;
    `cp -r $static $website`;
    `cp about.html contact.html $website`;

    # Call &process for each item below pictures tree
    finddepth { wanted => sub { process $_ },
              no_chdir => 1}, $pictures;

    # Exit successfully
    exit 0;
}

# Entry point for (re)generating individual web resources. Pass a
# filename or directory and the corresponding resource on the website
# will be updated if needed.
sub process {
    my $original = shift;
    return if ignore $original;
    if (update_needed $original) {
        thumbnail $original;

        if (-f $original) {
            if ((parent $original) =~ /$private_regex/) {
                scale $original;
            }
            else {
                scale_and_watermark $original;
            }
        }
    
        elsif (-d $original) {
            use Data::Dumper;
            say Dumper(create_gallery $original);
            say "\n\n\n\n\n\n=========================================================================================\n\n\n\n\\n";
            return;
            
            my $webdir = $website . path $original;
            my $index = $webdir . 'index.html';
            `mkdir -p $webdir`;
            
            # Write the index.html
            $tt->process(
            $template_file,
            { items => (create_gallery $original) },
            $index);
        }
    }
}

# Given an image directory, returns a reference to a list of hashes
# that represent gallery items, sorted by EXIF date
sub create_gallery {
    my $dir = shift;
    my @files = glob '$dir/*';
    my @gallery;

    for (@files) {
        my $gallery_item = {};
        next if ignore $_;

        if (-f) {
            my $exifdata = exif "$dir/$_";

            # Store image-specific info
            $gallery_item->{type}     = 'image';
            $gallery_item->{date}     = $exifdata->{date};
            $gallery_item->{settings} = $exifdata->{settings};
            $gallery_item->{url}  = (path $dir) . "thumbnails/$_";
        }
        elsif (-d) {
            next if (/$private_regex/ or /$hidden_regex/);
            
            # Store gallery-specific info
            $gallery_item->{type}    = 'gallery';
            $gallery_item->{date}    = dirdate $_;
            $gallery_item->{url} = (path $dir) . "thumbnails/all.jpg";
        }
        my ($width, $height) = imgsize $website . $gallery_item->{img};
        
        # Store remaining info
        $gallery_item->{width}  = $width;
        $gallery_item->{height} = $height;
        $gallery_item->{href} = (path "$dir/$_");
        $gallery_item->{title}  = (title $_);

        push @gallery, $gallery_item;
    }

    # Sort the list by EXIF date
    @gallery = sort {$b->{date} cmp $a->{date}} @gallery;

    return \@gallery;
}

# Returns some EXIF data of an image in a hash reference
sub exif {
    my $file = shift;
    my $data = {};
    my $exif = ImageInfo($file, 'MakerNote', 'Artist', 'Copyright', 'DateTimeOriginal', 'ExposureTime', 'FNumber', 'ISO');
    if (not %{$exif}) {
        die "EXIF info missing for $file, aborting...\n";
    }
    
    # If a raw file with the same name exists, copy over the EXIF data
    # to the file
    my $rawfile = $file;
    for my $ext ('dng', 'nef', 'cr2', 'crw') {
        $rawfile =~ s/\.jpg/\.$ext/;
        if (-f $rawfile) {
            # copy exif to jpeg
            last;
        }
    }

    $data->{date} = $exif->{DateTimeOriginal} or 0;
    $data->{settings} = "$exif->{ExposureTime}, $exif->{FNumber}, ISO $exif-{ISO}";
    return $data;
}

# Extracts the date from a directory name in EXIF format
sub dirdate {
    my $dir = shift;
    my $date;
    if ($dir =~ /($date_regex)/) {
        $date = $1;
        $date =~ s/-/:/g;
        $date .= " 00:00:00";
    }
    else {
        # todo: Return the last modified date as a fallback
        $date = '0000:00:00 00:00:000';
    }
    return $date;
}

# Returns true is the corresponding web resource is in need of an update
sub update_needed {
    my $original = shift;
    my $original_time;
    my $derivative = $website . path $original;
    my $derivative_time;

    if (-f $original) {
        $original_time = (stat $original)[9];
        $derivative_time = (stat $derivative)[9];
    }
    elsif (-d $original) {
        my $latest = (`ls $original -t1`)[0]; # todo: don't fork
        my $index = $derivative . 'index.html';
        $original_time = (stat "$original/$latest")[9];
        $derivative_time = (stat $index);
    }
    
    unless ($derivative_time) {
        return true;
    }
    else {
        return $original_time > $derivative_time;
    }
}

# Given an absolute path beneath the $pictures folder, returns the URL
# of the corresponding resource (which can be either an image or a
# gallery URL)
sub path {
    my $dir = shift;
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
# - the argument is a non-image file
# - the argument is a directory with less than 3 images
# - the argument is a directory from the @ignore list
sub ignore {
    my $candidate = shift;
    if (-f $candidate){
        return not is_image $candidate;;
    }
    elsif (-d $candidate) {
        my @listing = `ls -1`; # todo: don't fork
        return true if scalar @listing <= 3;
        return grep {$candidate =~ $_} @ignore;
    }
}

# Returns the display name of a file
sub title {
    my $file = name shift;
    $file =~ s/\.[^\.]+$//;
    $file =~ s/$date_regex //;
    return $file;
}

# Returns only the name of a file
sub name {
    my $file = shift;
    return (split m:/:, $file)[-1];
}

# Returns only the parent directory of a file
sub parent {
    my $file = shift;
    return (split m:/:, $file)[-2];
}

sub thumbnail {
    my $original = shift;
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
