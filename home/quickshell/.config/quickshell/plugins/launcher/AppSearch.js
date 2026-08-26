function text(entry) {
	if (!entry) return "";

	return [entry.name, entry.id].join(" ").toLowerCase();
}

function score(entry, query) {
	var q = String(query || "")
		.trim()
		.toLowerCase();
	var name = String((entry && entry.name) || "").toLowerCase();
	if (!q) return 0;
	if (name.indexOf(q) === 0) return 10000 - name.length;

	var index = text(entry).indexOf(q);
	return index < 0 ? -1 : 5000 - index;
}

function search(entries, query) {
	var rows = [];
	for (var i = 0; i < entries.length; i++) {
		var entry = entries[i];
		if (!entry || entry.noDisplay || !entry.name) continue;

		var rank = score(entry, query);
		if (rank < 0) continue;

		rows.push({
			entry: entry,
			rank: rank,
		});
	}
	rows.sort(function (a, b) {
		if (a.rank !== b.rank) return b.rank - a.rank;

		return String(a.entry.name).localeCompare(String(b.entry.name));
	});
	return rows;
}
