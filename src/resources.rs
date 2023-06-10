use bevy::prelude::*;

#[derive(Resource, Default)]
pub struct SimStats {
    pub num_cars_alive: usize,
    pub fitness: Vec<f32>,
    pub generation_count: u32,
    pub max_current_score: f32,
}

#[derive(Resource)]
pub struct Settings {
    pub is_show_rays: bool,
    pub is_hide_rays_at_start: bool,
    pub start_next_generation: bool,
    pub restart_sim: bool,
    pub is_camera_follow: bool,
}

#[derive(Resource, Default)]
pub struct BrainToDisplay(pub Vec<Vec<f64>>);

#[derive(Resource)]
pub struct MaxDistanceTravelled(pub f32);

impl Default for Settings {
    fn default() -> Self {
        Self {
            is_show_rays: true,
            is_hide_rays_at_start: true,
            start_next_generation: false,
            restart_sim: false,
            is_camera_follow: true,
        }
    }
}
