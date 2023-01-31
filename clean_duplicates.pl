use Modern::Perl;
use Koha::Biblios;
use Data::Dumper;
use Array::Utils qw(:all);
use List::MoreUtils qw(uniq);

use C4::Biblio qw(DelBiblio);

open(my $fh, '<', './duplicates');

my %biblionums_by_035a;
my %_035a_by_biblionum;

while (my $line = <$fh>) {
	my ($biblionumber, $_035a) = $line =~ /(\d+)\s+(.*)/;
	$biblionums_by_035a{$_035a} //= [];
	push @{$biblionums_by_035a{$_035a}}, $biblionumber;
	$_035a_by_biblionum{$biblionumber} //= [];
	push @{$_035a_by_biblionum{$biblionumber}}, $_035a;
}

# For multiple 035-values, make sure we have the same biblionumbers
# (and remove duplicate sets)
my %_035a_skip;

my @weird_matches;

sub process_duplicates {
	my ($current_035a, $_035a_by_biblionum, $biblionums_by_035a) = @_;
	my @biblionumbers_035a;
	my @biblionumbers;
	if (exists $biblionums_by_035a->{$current_035a}) {
		@biblionumbers = @{$biblionums_by_035a->{$current_035a}};
		delete $biblionums_by_035a->{$current_035a};
	}
	else {
		return ();
	}

	foreach my $biblionumber (@biblionumbers) {
		if (exists $_035a_by_biblionum->{$biblionumber}) {
			push @biblionumbers_035a, @{$_035a_by_biblionum->{$biblionumber}};
			delete $_035a_by_biblionum->{$biblionumber};
		}
	}
	my @biblionumbers_035a = uniq grep { $_ ne $current_035a } @biblionumbers_035a;

	return (@biblionumbers, map { process_duplicates($_, $_035a_by_biblionum, $biblionums_by_035a) } @biblionumbers_035a);
}

while (my ($_035a, $biblionumbers) = each %biblionums_by_035a) {
	if (exists $_035a_skip{$_035a}) {
		print "Allready processed, skipping\n";
	}
	next if exists $_035a_skip{$_035a};
	my $duplicates_hash = join ('#', sort { $a <=> $b } @{$biblionumbers});

	foreach my $biblionumber (@{$biblionumbers}) {
		if (@{$_035a_by_biblionum{$biblionumber}} > 1) {
			my @other_035a = grep { $_ ne $_035a } @{$_035a_by_biblionum{$biblionumber}};
			foreach my $other_035a (@other_035a) {
				$_035a_skip{$other_035a} = 1;
				my $other_duplicates_hash = join('#', sort { $a <=> $b } @{$biblionums_by_035a{$other_035a}});
				if ($duplicates_hash ne $other_duplicates_hash) {
					$_035a_skip{$_035a} = 1;
					push @weird_matches, {
						current_035a => $_035a,
						current_biblios => $duplicates_hash,
						other_035a => $other_035a,
						other_biblios => $other_duplicates_hash
					}
				}
				else {
					print "SUCCESS\n";
				}
			}
		}
	}
}

#foreach my $match (@weird_matches) {
#	my @matches = uniq process_duplicates($match->{current_035a}, { %_035a_by_biblionum }, { %biblionums_by_035a });
#	print Dumper(\@matches);
#}

my @all_duplicates_with_items;
my @all_duplicates_with_non_original_items;
DUPLICATES: while (my ($_035a, $biblionumbers) = each %biblionums_by_035a) {
	next if exists $_035a_skip{$_035a};
	my @bibnums = sort { $a <=> $b } @{$biblionumbers};
	my $orig_bibnum = shift @bibnums;
	my @duplicates_with_items;
	for my $biblionumber (@bibnums) {
		my $biblio = Koha::Biblios->find( $biblionumber);
		if (!$biblio) {
			warn "Biblio $biblionumber does not exist!";
			next DUPLICATES;
		}
		if ($biblio->items->count) {
			push @duplicates_with_items, $biblionumber;
		}
	}
	if (@duplicates_with_items) {
		my $orig_biblio_has_items = Koha::Biblios->find( $orig_bibnum )->items->count();
		if (!$orig_biblio_has_items && @duplicates_with_items == 1) {
			print "Original biblio $orig_bibnum missing items, replacing with $duplicates_with_items[0]\n";
			push @all_duplicates_with_non_original_items, [$orig_bibnum, $duplicates_with_items[0]];
		}
		else {
			#my $tmp = $orig_biblio_has_items ? [$orig_bibnum] : [];
			#my $tmp = $orig_biblio_has_items ? [$orig_bibnum] : [];
			#push @{$tmp}, @duplicates_with_items;
			push @all_duplicates_with_items, [$orig_bibnum, @duplicates_with_items];
			next DUPLICATES;
		}
	}
	else {
		# Remove duplicates
		foreach my $biblionumber (@bibnums) {
			print "REMOVING DUPLICATE: $biblionumber\n"
			#DelBiblio($biblionumber);
		}
	}
}
print "DUPLICATES WITH ITEMS\n";
print Dumper(\@all_duplicates_with_items);

print "DUPLICATES WITH NON ORIGINAL ITEMS\n\n";

foreach my $set (@all_duplicates_with_non_original_items) {
	print "https://koha-intra.ub.gu.se/cgi-bin/koha/catalogue/detail.pl?$set->[0]\n";
	print "https://koha-intra.ub.gu.se/cgi-bin/koha/catalogue/detail.pl?$set->[1]\n\n";
}
