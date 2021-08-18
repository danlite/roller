## Usage

- `npm run build:static` is the main function, which generates an index of the rollables
  and copies it and the rollable YAML files into the client `dist/` folder
- `npm run start` doesn't work with the client's latest method of loading rollables
  (which expects a static index and YAML files hosted on the same web server)
