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
