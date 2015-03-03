## Photog!

Photog! generates a unique, hierarchical, and chronologically sorted
photography website, complete with thumbnails and watermarked images,
based on a user's $HOME/Pictures folder.

##Installation instructions

The installation of Photog! has been tested on Debian GNU/Linux and
Mac OSX. It should work on Windows, but as it uses some Unix utilities
(ls and grep) it needs a Unix compatibility layer (Cygwin) to run
successfully.

First, make sure you have ImageMagick (http://imagemagick.org/)
installed (e.g., apt-get install imagemagick or brew install
imagemagick).

Second, you need Dist::Zilla, which can be installed by running
the following command as root:

   cpan Dist::Zilla

After that, make sure you're in the directory where this INSTALL file
is, and run the following command as root:

    dzil install

After installation, a manpage is available with the following command:

    man photog

Also, the command named `photog` should be available. To generate a
photography website using default settings, simply type `photog` and
enjoy!
