// iOS entrypoint. The Rust static library exports `main_rs` (see src/lib.rs),
// which builds the Bevy app and starts winit's UIKit event loop. winit drives
// UIApplicationMain internally, so this call does not return.
extern void main_rs(void);

int main(int argc, char *argv[]) {
    main_rs();
    return 0;
}
