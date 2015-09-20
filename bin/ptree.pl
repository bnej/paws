use Pod::Abstract;

my $file = $ARGV[0];
my $pa = Pod::Abstract->load_file($file);

print $pa->ptree;
