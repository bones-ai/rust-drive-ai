use bevy::prelude::*;
use rand::distributions::WeightedIndex;
use rand::prelude::Distribution;

use crate::*;
use crate::car::{Brain, Car, CarBundle, Fitness};
use crate::enemy::{BoundControlTruck, Enemy, spawn_bound_trucks, spawn_enemies};
use crate::nn::Net;

pub struct PopulationPlugin;

impl Plugin for PopulationPlugin {
    fn build(&self, app: &mut bevy::prelude::App) {
        app.insert_resource(MaxDistanceTravelled(0.0))
            .add_systems(Startup, setup)
            .add_systems(Update, population_stats_system)
            .add_systems(Update, generation_reset_system);
    }
}

fn setup(mut commands: Commands, mut settings: ResMut<Settings>, asset_server: Res<AssetServer>) {
    spawn_cars(&mut commands, &asset_server, &mut settings, None);
}

fn population_stats_system(
    mut sim_stats: ResMut<SimStats>,
    mut max_distance_travelled: ResMut<MaxDistanceTravelled>,
    mut brain_on_display: ResMut<BrainToDisplay>,
    mut query: Query<(Entity, &Transform, &Brain, &mut Fitness), With<Car>>,
) {
    let mut max_fitness = 0.0;
    sim_stats.num_cars_alive = query.iter().len();
    let mut best_entity = None;

    for (entity, transform, _, mut fitness) in query.iter_mut() {
        fitness.0 = calc_fitness(transform);
        if fitness.0 > max_fitness {
            max_fitness = fitness.0;
            best_entity=Some(entity);
            // brain_on_display.0 = brain.nn_outputs.clone();
            sim_stats.max_current_score = fitness.0;
            max_distance_travelled.0 = transform.translation.y;
        }
    }
    if let Some(entity) = best_entity {
        let br: &Brain = query.get_component(entity).unwrap();
        brain_on_display.1 = br.nn.clone();
        brain_on_display.0 = br.nn_outputs.clone();
    }
}

fn generation_reset_system(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    mut settings: ResMut<Settings>,
    mut sim_stats: ResMut<SimStats>,
    brain_on_display: ResMut<BrainToDisplay>,
    // mut nnsave: ResMut<NNSave>,
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

    let mut best_fitness = 0.0;
    let mut best_idx = 0;

    for (idx, (e, brain, fitness)) in cars_query.iter().enumerate() {
        if fitness.0 > best_fitness {
            best_fitness = fitness.0;
            best_idx = idx;
        }
        fitnesses.push(fitness.0);
        old_brains.push(brain.nn.clone());

        commands.entity(e).despawn();
    }

    let (max_fitness, gene_pool) = create_gene_pool(fitnesses);
    let mut rng = rand::thread_rng();
    let mut new_brains = Vec::new();


    if settings.should_save {
        brain_on_display.1.save_net(NN_SAVE_FILE);
        // brain_on_display.0
        // old_brains[best_idx].save_net(NN_SAVE_FILE);
    }
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
    if !settings.already_loaded {
        settings.already_loaded = true;
        if let Ok(brain) = CarBundle::load_brain() {
            for _ in 0..NUM_AI_CARS {
                let mut new_brain = brain.clone();
                new_brain.mutate();
                let new_car = CarBundle::with_brain(
                    asset_server,
                    new_brain,
                );
                commands.spawn(new_car);
            }
            return;
        }
    }
    let brains = brains.unwrap_or(Vec::new());
    let is_new_nn = brains.is_empty() || settings.restart_sim;
    settings.restart_sim = false;
    if is_new_nn {
        for _ in 0..NUM_AI_CARS {
            commands.spawn(CarBundle::new(asset_server));
        }
    } else {
        for brain in brains.into_iter() {
            let new_car = CarBundle::with_brain(
                asset_server,
                brain,
            );
            commands.spawn(new_car);
        }
    }
}

fn create_gene_pool(values: Vec<f32>) -> (f32, WeightedIndex<f32>) {
    let max_fitness = values.iter()
        .copied()
        .reduce(|a, b| a.max(b))
        .unwrap_or(0.0);

    let weights = values;

    (
        max_fitness,
        WeightedIndex::new(weights).expect("Failed to generate gene pool"),
    )
}

fn calc_fitness(transform: &Transform) -> f32 {
    let y = transform.translation.y;
    if y <= 600.0 {
        return 0.1;
    }

    return transform.translation.y / 340.0;
}
