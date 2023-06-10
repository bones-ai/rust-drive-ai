use bevy::prelude::*;
use rand::distributions::WeightedIndex;
use rand::prelude::Distribution;

use crate::car::{Brain, Car, CarBundle, Fitness};
use crate::enemy::{spawn_bound_trucks, spawn_enemies, BoundControlTruck, Enemy};
use crate::nn::Net;
use crate::*;

pub struct PopulationPlugin;

impl Plugin for PopulationPlugin {
    fn build(&self, app: &mut bevy::prelude::App) {
        app.insert_resource(MaxDistanceTravelled(0.0))
            .add_startup_system(setup)
            .add_system(population_stats_system)
            .add_system(generation_reset_system);
    }
}

fn setup(mut commands: Commands, mut settings: ResMut<Settings>, asset_server: Res<AssetServer>) {
    spawn_cars(&mut commands, &asset_server, &mut settings, None);
}

fn population_stats_system(
    mut sim_stats: ResMut<SimStats>,
    mut max_distance_travelled: ResMut<MaxDistanceTravelled>,
    mut brain_on_display: ResMut<BrainToDisplay>,
    mut query: Query<(&Transform, &Brain, &mut Fitness), With<Car>>,
) {
    let mut max_fitness = 0.0;
    sim_stats.num_cars_alive = query.iter().len();

    for (transform, brain, mut fitness) in query.iter_mut() {
        fitness.0 = calc_fitness(transform);
        if fitness.0 > max_fitness {
            max_fitness = fitness.0;
            brain_on_display.0 = brain.nn_outputs.clone();
            sim_stats.max_current_score = fitness.0;
            max_distance_travelled.0 = transform.translation.y;
        }
    }
}

fn generation_reset_system(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    mut settings: ResMut<Settings>,
    mut sim_stats: ResMut<SimStats>,
    cars_query: Query<(Entity, &Brain, &Fitness)>,
    cars_count_query: Query<With<Car>>,
    enemy_query: Query<Entity, With<Enemy>>,
    bounds_truck_query: Query<Entity, With<BoundControlTruck>>,
) {
    let num_cars = cars_count_query.iter().count();
    if num_cars > 0 {
        return;
    }

    bounds_truck_query.for_each(|t| commands.entity(t).despawn());
    enemy_query.for_each(|e| commands.entity(e).despawn());

    let mut fitnesses = Vec::new();
    let mut old_brains = Vec::new();
    for (e, brain, fitness) in cars_query.iter() {
        fitnesses.push(fitness.0);
        old_brains.push(brain.nn.clone());

        commands.entity(e).despawn();
    }

    let (max_fitness, gene_pool) = create_gene_pool(fitnesses);
    let mut rng = rand::thread_rng();
    let mut new_brains = Vec::new();

    for _ in 0..NUM_AI_CARS {
        let brain_idx = gene_pool.sample(&mut rng);
        let mut rand_brain = old_brains[brain_idx].clone();
        rand_brain.mutate();
        new_brains.push(rand_brain);
    }

    // update stats
    sim_stats.generation_count += 1;
    sim_stats.fitness.push(max_fitness);

    // respawn everything
    spawn_enemies(&mut commands, &asset_server);
    spawn_bound_trucks(&mut commands, &asset_server);
    spawn_cars(
        &mut commands,
        &asset_server,
        &mut settings,
        Some(new_brains),
    );
}

fn spawn_cars(
    commands: &mut Commands,
    asset_server: &AssetServer,
    settings: &mut Settings,
    brains: Option<Vec<Net>>,
) {
    let brains = brains.unwrap_or(Vec::new());
    let is_new_nn = brains.is_empty() || settings.restart_sim;
    settings.restart_sim = false;

    for i in 0..NUM_AI_CARS {
        match is_new_nn {
            true => commands.spawn(CarBundle::new(asset_server)),
            false => commands.spawn(CarBundle::with_brain(
                asset_server,
                &brains.get(i as usize).unwrap(),
            )),
        };
    }
}

fn create_gene_pool(values: Vec<f32>) -> (f32, WeightedIndex<f32>) {
    let mut max_fitness = 0.0;
    let mut weights = Vec::new();

    for v in values.iter() {
        if *v > max_fitness {
            max_fitness = *v;
        }
        weights.push(*v);
    }

    (
        max_fitness,
        WeightedIndex::new(&weights).expect("Failed to generate gene pool"),
    )
}

fn calc_fitness(transform: &Transform) -> f32 {
    let y = transform.translation.y;
    if y <= 600.0 {
        return 0.1;
    }

    return transform.translation.y / 340.0;
}
