.pragma library

// Which icon-theme name to show for a file or folder: Papirus' file-type and
// place icons, chosen by extension - fast, and right for what a person can
// see in a name. FileIcon.qml falls back to the drawn outlines when the
// theme has none.

const byExtension = {
	pdf: "application-pdf", epub: "application-epub+zip",
	png: "image-png", jpg: "image-jpeg", jpeg: "image-jpeg", gif: "image-gif",
	webp: "image-x-generic", bmp: "image-x-generic", heic: "image-x-generic", avif: "image-x-generic",
	tif: "image-x-generic", tiff: "image-x-generic", svg: "image-svg+xml", ico: "image-x-generic",
	md: "text-markdown", markdown: "text-markdown", txt: "text-plain", log: "text-x-log",
	csv: "text-csv", rst: "text-plain",
	py: "text-x-python", sh: "application-x-shellscript", bash: "application-x-shellscript",
	zsh: "application-x-shellscript", fish: "application-x-shellscript",
	js: "text-x-javascript", mjs: "text-x-javascript", ts: "text-x-javascript",
	json: "application-json", html: "text-html", htm: "text-html", css: "text-css",
	c: "text-x-csrc", h: "text-x-csrc", cpp: "text-x-c++src", cc: "text-x-c++src", hpp: "text-x-c++src",
	qml: "text-x-qml", lua: "text-x-lua", rs: "text-x-rust", go: "text-x-go",
	yml: "text-x-script", yaml: "text-x-script", toml: "text-x-script", ini: "text-x-script",
	conf: "text-x-script", xml: "text-x-script", patch: "text-x-patch", diff: "text-x-patch",
	desktop: "application-x-desktop", service: "text-x-script", timer: "text-x-script",
	pem: "application-x-pem-key", key: "application-x-pem-key",
	mp3: "audio-x-generic", flac: "audio-x-generic", ogg: "audio-x-generic", wav: "audio-x-generic",
	m4a: "audio-x-generic", opus: "audio-x-generic",
	mp4: "video-x-generic", mkv: "video-x-generic", webm: "video-x-generic", mov: "video-x-generic",
	avi: "video-x-generic",
	zip: "application-zip", tar: "application-x-tar", gz: "application-x-compressed-tar",
	tgz: "application-x-compressed-tar", xz: "application-x-compressed-tar", zst: "application-x-compressed-tar",
	bz2: "application-x-compressed-tar", "7z": "application-x-archive", rar: "application-x-archive",
	iso: "application-x-cd-image", img: "application-x-cd-image",
	doc: "x-office-document", docx: "x-office-document", odt: "x-office-document", rtf: "x-office-document",
	xls: "x-office-spreadsheet", xlsx: "x-office-spreadsheet", ods: "x-office-spreadsheet",
	ppt: "x-office-presentation", pptx: "x-office-presentation", odp: "x-office-presentation",
	ttf: "font-x-generic", otf: "font-x-generic", woff: "font-x-generic", woff2: "font-x-generic",
	sqlite: "application-x-sqlite3", db: "application-x-sqlite3",
	appimage: "application-x-executable"
};

const byName = {
	"Makefile": "text-x-makefile", "PKGBUILD": "application-x-shellscript",
	"LICENSE": "text-plain", "README": "text-plain"
};

// The folders a home directory has by name, and the places.
const folders = {
	"Downloads": "folder-download", "Documents": "folder-documents", "Pictures": "folder-pictures",
	"Music": "folder-music", "Videos": "folder-videos", "Desktop": "user-desktop",
	"Templates": "folder-templates", "Public": "folder-publicshare"
};

// name: the file's name; folder: whether it is one; path: its full path;
// home: the user's home directory.
function name(fileName, folder, path, home) {
	if (folder) {
		if (path === home)
			return "user-home";
		if (path.indexOf("/.local/share/Trash") >= 0 && path.endsWith("/files"))
			return "user-trash";
		if (fileName === ".git")
			return "folder-git";
		if (path === home + "/" + fileName && folders[fileName] !== undefined)
			return folders[fileName];
		return "folder";
	}
	if (byName[fileName] !== undefined)
		return byName[fileName];
	const dot = fileName.lastIndexOf(".");
	const ext = dot > 0 ? fileName.slice(dot + 1).toLowerCase() : "";
	return byExtension[ext] ?? (ext === "" ? "text-x-generic" : "unknown");
}
