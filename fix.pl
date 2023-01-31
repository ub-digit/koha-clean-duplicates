use strict;

use Encode qw(encode);
use MARC::Batch;
use Data::Dumper;
use Koha::SearchEngine;
use Koha::SearchEngine::Search;

my $searcher = Koha::SearchEngine::Search->new({ index => $Koha::SearchEngine::BIBLIOS_INDEX });

open(my $fh, '<', './multiple_matches');
while (my $control_number = <$fh>) {
	chomp($control_number);
	my $query = "system-control-number.raw:\"$control_number\"";

	print $control_number;
}
exit;
#foreach my $file (@files) {
#		my $control_number = $record->subfield('035', 'a');
#		my $query = "system-control-number.raw:\"$control_number\"";
#		my ($error, $results) = $searcher->simple_search_compat($query, 0, 3, ['biblioserver']);
#		if (@{$results} > 1) {
#			print $control_number. "\n";
#		}
#	}
#}
