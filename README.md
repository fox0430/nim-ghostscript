# nim-ghostscript

Nim bindings for [Ghostscript](https://ghostscript.com).

## Requirements

- [Nim](https://nim-lang.org) 2.0.6+
- [Ghostscript](https://ghostscript.com)

## Installtion
```bash
nimble install ghostscript
```

## Usage

```nim
import pkg/ghostscript

# Convert PDF to PNG
let gs = newGhostscript()
gs.init(@[
  "-dSAFER",
  "-dBATCH",
  "-dNOPAUSE",
  "-sDEVICE=png16m",
  "-r300",
  "-sOutputFile=output.png",
  "input.pdf"
])
gs.close()
```

## License

MIT

> [!NOTE]
> This binding is licensed under MIT, but Ghostscript itself is licensed under [AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0.html). When using this library, your application must comply with the AGPL-3.0 terms, or you must obtain a [commercial license](https://artifex.com/licensing/) from Artifex.
