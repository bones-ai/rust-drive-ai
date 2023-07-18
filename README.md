# Drive AI

Drive AI is a ambitious experiement pushing the boundaries of verfiable compute. The road-fighter inspired simulation environment is implemented with [Dojo](https://github.com/dojoengine/dojo), a provable game engine which enables zero knowledge proofs to be generated attesting to the integrity of a computation.

In the simulation, a car is controlled by a neural network and is tasked with navigating traffic in it's environment. The car recives inputs from it's sensors, passes them to its neural network and outputs a control for the direction of the car.

In this demo, a neural network is trained in the simulation environment offchain. Once a model is defined, it can be exported and benchmarked in the provable simulation. All physics and neural network inference occurs in realtime and zero knowledge proofs of the computation are produced asynchonously. The 

Built with [Dojo](https://github.com/dojoengine/dojo), [Rust](https://www.rust-lang.org/) and [Bevy](https://bevyengine.org/) game engine

![gui](/gui.png)

## Usage
- Clone the repo
    ```
    git clone git@github.com:cartridge-gg/drive-ai.git
    cd drive-ai
    ```
<!-- - Run the simulation in the browser -->
<!--     ``` --> 
<!--     cargo run --target wasm32-unknown-unknown -->
<!--     ``` -->
<!-- - Build the simulation for distribution -->
<!--     ``` -->
<!--     cargo build --release --target wasm32-unknown-unknown -->
<!--     wasm-bindgen --out-dir ./out/ --target web ./target/wasm32-unknown-unknown/release/steering.wasm -->
<!--     ``` -->
- Run the simulation
    ```
    cargo run
    ```
## Configurations
- The project config file is located at `src/configs.rs`

## Assets
- [https://www.spriters-resource.com/nes/roadfighter/sheet/57232/](https://www.spriters-resource.com/nes/roadfighter/sheet/57232/)
- Font - [https://code807.itch.io/magero](https://code807.itch.io/magero)

## Acknowledgements

This game is based on the great work of the original rust implementation found here: https://github.com/bones-ai/rust-drive-ai
