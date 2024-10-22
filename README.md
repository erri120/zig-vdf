# VDF Parser

Parser for Steam's VDF/ACF text files:

```
"libraryfolders"
{
	"0"
	{
		"path"		"/home/user/.local/share/Steam"
		"label"		""
		"contentid"		"4129378406094616110"
		"totalsize"		"0"
		"update_clean_bytes_tally"		"7739471951"
		"time_last_update_corruption"		"0"
		"apps"
		{
			"228980"		"482069544"
			"365670"		"1519822497"
			"1391110"		"646598402"
			"1493710"		"1209309065"
			"1628350"		"739531978"
			"1826330"		"274110"
			"2348590"		"1224814506"
		}
	}
}
```

## Usage

### CLI

The program `vdf` converts VDF/ACF files into JSON:

```json
{
    "libraryfolders": {
        "0": {
            "path": "/home/user/.local/share/Steam",
            "label": "",
            "contentid": "4129378406094616110",
            "totalsize": "0",
            "update_clean_bytes_tally": "7739471951",
            "time_last_update_corruption": "0",
            "apps": {
                "228980": "482069544",
                "365670": "1519822497",
                "1391110": "646598402",
                "1493710": "1209309065",
                "1628350": "739531978",
                "1826330": "274110",
                "2348590": "1224814506"
            }
        }
    }
}
```

### Library

```bash
zig fetch --save https://github.com/erri120/zig-vdf/archive/refs/heads/main.tar.gz
```

In your `build.zig` file:

```zig
const vdf = b.dependency("vdf", .{
    .target = target,
    .optimize = optimize,
});

lib.root_module.addImport("vdf", vdf.module("vdf"));
```

The module can now be imported:

```zig
const vdf = @import("vdf");
```

## License

See [LICENSE](./LICENSE).

