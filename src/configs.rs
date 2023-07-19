use bevy::prelude::Color;

/// Main
pub const NUM_ROAD_TILES: u32 = 1;
pub const ROAD_SPRITE_W: f32 = 160.0;
pub const ROAD_SPRITE_H: f32 = 288.0;
pub const NUM_ENEMY_CARS: u32 = 140;
pub const SPRITE_SCALE_FACTOR: f32 = 6.0;
pub const BACKGROUND_COLOR: Color = Color::BLACK;
pub const WINDOW_WIDTH: f32 = ROAD_SPRITE_W * SPRITE_SCALE_FACTOR;
pub const WINDOW_HEIGHT: f32 = 1000.0;

pub const ROAD_X_MIN: f32 = 238.0; // TODO: compute with SPRITE_SCALE_FACTOR
pub const ROAD_X_MAX: f32 = 718.0;
// TODO: subtract starting line (window / 2)
pub const ROAD_W: f32 = ROAD_X_MAX - ROAD_X_MIN;
// TODO: subtract goal position ()
pub const ROAD_H: f32 = WINDOW_HEIGHT * NUM_ROAD_TILES as f32;
pub const DOJO_TO_BEVY_RATIO_X: f32 = ROAD_W / DOJO_GRID_WIDTH;
pub const DOJO_TO_BEVY_RATIO_Y: f32 = ROAD_H / DOJO_GRID_HEIGHT;

/// Car
pub const NUM_AI_CARS: u32 = 1;
pub const TURN_SPEED: f32 = 25.0;
pub const CAR_THRUST: f32 = 5.0 * 100.0;
pub const MAX_SPEED: f32 = 10.0 * 300.0;
pub const FRICTION: f32 = 30.0 * 100.0;
pub const MIN_SPEED_TO_STEER: f32 = 50.0;
pub const NUM_RAY_CASTS: u32 = 8;
pub const RAYCAST_SPREAD_ANGLE_DEG: f32 = 140.0;
pub const RAYCAST_START_ANGLE_DEG: f32 = 20.0;
pub const RAYCAST_MAX_TOI: f32 = 250.0;
// pub const RAYCAST_THICKNESS: f32 = 0.3;

/// NN
pub const NUM_HIDDEN_NODES: usize = 15;
pub const NUM_OUPUT_NODES: usize = 3;
pub const NN_VIZ_NODE_RADIUS: f32 = 10.0;
pub const NN_W_ACTIVATION_THRESHOLD: f64 = 0.3;
pub const NN_S_ACTIVATION_THRESHOLD: f64 = 0.8;

/// Others
pub const FONT_RES_PATH: &str = "Magero.ttf";

/// Dojo
pub const JSON_RPC_ENDPOINT: &str = "http://0.0.0.0:5050";
pub const ACCOUNT_ADDRESS: &str =
    "0x03ee9e18edc71a6df30ac3aca2e0b02a198fbce19b7480a63a0d71cbd76652e0"; // katana account 0
pub const ACCOUNT_SECRET_KEY: &str =
    "0x0300001800000000300000180000000000030000000000003006001800006600";
pub const WORLD_ADDRESS: &str = "0x26065106fa319c3981618e7567480a50132f23932226a51c219ffb8e47daa84";
pub const DOJO_SYNC_INTERVAL: f32 = 0.1;
pub const DOJO_GRID_WIDTH: f32 = 400.0;
pub const DOJO_GRID_HEIGHT: f32 = 1000.0;
pub const DOJO_ENEMIES_NB: u32 = 10;
