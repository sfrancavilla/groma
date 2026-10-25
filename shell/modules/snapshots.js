.pragma library

// Snapshot descriptions, in words. Shared by the snapshot-boot sheet and the
// Snapshots view, so both say the same thing about the same snapshot.

// snap-pac names a pre snapshot after the pacman command that followed
// it, and a post after the packages it touched. Said in words: "a system
// update", "installing gradle", "removing gradle".
function phrase(kind, text) {
	if (text === "")
		return "";
	if (kind !== "pre") {
		const names = text.split(/\s+/).filter(n => n !== "");
		return names.length <= 3 ? names.join(", ") : `${names.slice(0, 3).join(", ")} and ${names.length - 3} more`;
	}
	const words = text.split(/\s+/);
	if (words[0] !== "pacman")
		return text;
	const ops = words.filter(w => /^-[A-Za-z]+$/.test(w)).join("");
	// The packages: every word that is not a flag, skipping the values of
	// the flags that take one ("--config /etc/pacman.conf").
	const valued = ["--config", "--dbpath", "--root", "--cachedir", "--gpgdir", "--hookdir", "--logfile", "--arch"];
	const targets = [];
	for (let i = 1; i < words.length; i++) {
		if (valued.includes(words[i])) {
			i++;
			continue;
		}
		if (!words[i].startsWith("-") && words[i] !== "")
			targets.push(words[i]);
	}
	const what = targets.length === 0 ? "" : targets.length <= 2 ? " " + targets.map(t => t.split("/").pop()).join(" and ")
		: ` ${targets.length} packages`;
	if (/S/.test(ops) && /y/.test(ops) && /u/.test(ops))
		return "a system update";
	if (/U/.test(ops))
		return "installing a built package" + (text.includes("yay") ? " from the AUR" : "");
	if (/R/.test(ops))
		return "removing" + (what || " packages");
	if (/S/.test(ops))
		return "installing" + (what || " packages");
	return text;
}

// A pre/post pair as one sentence-case title: "System update", "Installing
// gradle", "Removing gradle".
function title(preDescription) {
	const p = phrase("pre", preDescription).replace(/^a /, "");
	return p === "" ? "Change" : p.charAt(0).toUpperCase() + p.slice(1);
}
