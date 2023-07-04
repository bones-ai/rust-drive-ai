use bevy::prelude::Color;

/// Main
pub const NUM_ROAD_TILES: u32 = 20;
pub const ROAD_SPRITE_W: f32 = 160.0;
pub const ROAD_SPRITE_H: f32 = 288.0;
pub const NUM_ENEMY_CARS: u32 = 140;
pub const SPRITE_SCALE_FACTOR: f32 = 6.0;
pub const BACKGROUND_COLOR: Color = Color::BLACK;
pub const WINDOW_WIDTH: f32 = 1980.0;
pub const WINDOW_HEIGHT: f32 = 1080.0;

/// Car
pub const NUM_AI_CARS: u32 = 100;
pub const TURN_SPEED: f32 = 25.0;
pub const CAR_THRUST: f32 = 5.0 * 100.0;
pub const MAX_SPEED: f32 = 10.0 * 300.0;
pub const FRICTION: f32 = 30.0 * 100.0;
pub const MIN_SPEED_TO_STEER: f32 = 50.0;
pub const NUM_RAY_CASTS: u32 = 15;
pub const RAYCAST_SPREAD_ANGLE_DEG: f32 = 130.0;
pub const RAYCAST_START_ANGLE_DEG: f32 = 20.0;
pub const RAYCAST_MAX_TOI: f32 = 200.0;
// pub const RAYCAST_THICKNESS: f32 = 0.3;

/// NN
pub const NUM_HIDDEN_NODES: usize = 15;
pub const NUM_OUPUT_NODES: usize = 3;
pub const NN_VIZ_NODE_RADIUS: f32 = 10.0;
pub const NN_W_ACTIVATION_THRESHOLD: f64 = 0.3;
pub const NN_S_ACTIVATION_THRESHOLD: f64 = 0.8;

/// Others
pub const FONT_RES_PATH: &str = "Magero.ttf";
