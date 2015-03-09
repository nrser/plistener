# plistener

<!-- summary -->

watch OSX plist preference files and record changes.

<!-- /summary -->
<!-- description -->

this is alpha-as-fuck. please use with caution.

it watches preference files stored as `.plist` on OSX and reports changes.

<!-- /description -->

## CLI

### run

<!-- run:description -->

run the listener from the terminal, dumping to stdout.

<!-- /run:description -->
<!-- run:syntax -->
    
    plistener run [options] [working_dir=.]

<!-- /run:syntax -->

### clear

<!-- clear:description -->

remove all the change files in `<working_dir>/changes`.

<!-- /clear:description -->
<!-- clear:syntax -->
    
    plistener clear [working_dir=.]

<!-- /clear:syntax -->

### reset

<!-- reset:description -->

remove all data in `<working_dir>/data` and change files in `<working_dir>/changes`.

<!-- /reset:description -->
<!-- reset:syntax -->
    
    plistener reset [working_dir=.]

<!-- /reset:syntax -->
