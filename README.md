# AI learns to drive
AI learns to drive in a road-fighter inspired environment

The cars are controlled using a neural network, and are trained using a genetic algorithm.

Built with [Rust](https://www.rust-lang.org/) and [Bevy](https://bevyengine.org/) game engine

![gui](/gui.png)

# Demo
Here's the entire timelapse of the AI learning to drive

[![youtube](https://img.youtube.com/vi/H7RWcNgE-6s/0.jpg)](https://youtu.be/H7RWcNgE-6s)

## Usage
- Clone the repo
    ```
    git clone git@github.com:bones-ai/rust-drive-ai.git
    cd rust-drive-ai
    ```
- Run the simulation in the browser
    ``` 
    cargo run --target wasm32-unknown-unknown
    ```
- Build the simulation for distribution
    ```
    cargo build --release --target wasm32-unknown-unknown
    wasm-bindgen --out-dir ./out/ --target web ./target/wasm32-unknown-unknown/release/steering.wasm
    ```
## Configurations
- The project config file is located at `src/configs.rs`

## Assets
- [https://www.spriters-resource.com/nes/roadfighter/sheet/57232/](https://www.spriters-resource.com/nes/roadfighter/sheet/57232/)
- Font - [https://code807.itch.io/magero](https://code807.itch.io/magero)
