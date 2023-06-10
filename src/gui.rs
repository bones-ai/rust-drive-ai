use bevy::prelude::*;
use bevy_inspector_egui::{
    bevy_egui::EguiContexts,
    egui::{
        self,
        epaint::CircleShape,
        plot::{Line, Plot, PlotPoints},
        pos2, Color32, Shape, Stroke,
    },
};

use crate::*;

pub struct GuiPlugin;

#[derive(Component)]
struct GenerationCountLabel;
#[derive(Component)]
struct MaxScoreLabel;
#[derive(Component)]
struct CarsAliveLabel;
#[derive(Component)]
struct CarProgressIcon;

impl Plugin for GuiPlugin {
    fn build(&self, app: &mut bevy::prelude::App) {
        app.add_startup_system(setup)
            .insert_resource(BrainToDisplay::default())
            .insert_resource(Settings::default())
            .insert_resource(SimStats::default())
            .add_system(stats_dialog_system)
            .add_system(generation_count_stats_system)
            .add_system(max_score_stats_system)
            .add_system(num_cars_stats_system)
            .add_system(car_progress_system)
            .add_system(nn_viz_system);
    }
}

fn setup(mut commands: Commands, asset_server: Res<AssetServer>) {
    // gui
    let font = asset_server.load(FONT_RES_PATH);
    let text_style = TextStyle {
        font: font.clone(),
        font_size: 40.0,
        color: Color::WHITE,
    };

    // Root
    commands
        .spawn(NodeBundle {
            style: Style {
                size: Size::width(Val::Percent(100.0)),
                justify_content: JustifyContent::SpaceBetween,
                ..default()
            },
            ..default()
        })
        // Left container for progress
        .with_children(|parent| {
            parent
                .spawn(NodeBundle {
                    style: Style {
                        size: Size::width(Val::Percent(80.0)),
                        ..default()
                    },
                    ..default()
                })
                .with_children(|parent| {
                    // Left UI gap behind egui nn viz
                    parent.spawn(NodeBundle {
                        style: Style {
                            // size: Size::width(Val::Percent(28.0)),
                            size: Size::width(Val::Px(415.0)),
                            ..default()
                        },
                        ..default()
                    });

                    // Progress lane
                    parent
                        .spawn(NodeBundle {
                            style: Style {
                                flex_direction: FlexDirection::Column,
                                size: Size::width(Val::Percent(3.0)),
                                align_content: AlignContent::SpaceBetween,
                                justify_content: JustifyContent::SpaceBetween,
                                ..default()
                            },
                            background_color: BackgroundColor(Color::rgb_u8(106, 108, 105)),
                            ..default()
                        })
                        .with_children(|parent| {
                            // Top flag
                            parent.spawn(ImageBundle {
                                image: asset_server.load("flag-top.png").into(),
                                style: Style {
                                    size: Size::new(Val::Px(32.0), Val::Px(32.0)),
                                    margin: UiRect::all(Val::Px(5.0)),
                                    ..default()
                                },
                                ..default()
                            });
                            // Bottom flag
                            parent.spawn(ImageBundle {
                                image: asset_server.load("flag-bottom.png").into(),
                                style: Style {
                                    size: Size::new(Val::Px(32.0), Val::Px(32.0)),
                                    margin: UiRect::all(Val::Px(5.0)),
                                    ..default()
                                },
                                ..default()
                            });
                        });
                });

            // Right stats column
            parent
                .spawn(NodeBundle {
                    style: Style {
                        size: Size::width(Val::Percent(20.0)),
                        border: UiRect::all(Val::Px(40.0)),
                        flex_direction: FlexDirection::Column,
                        justify_content: JustifyContent::Start,
                        align_items: AlignItems::Center,
                        gap: Size::new(Val::Px(8.0), Val::Px(8.0)),
                        ..default()
                    },
                    background_color: BackgroundColor(Color::BLACK),
                    ..default()
                })
                .with_children(|parent| {
                    parent.spawn((
                        TextBundle::from_section("Gen:", text_style.clone())
                            .with_text_alignment(TextAlignment::Center)
                            .with_style(Style {
                                flex_direction: FlexDirection::Row,
                                justify_content: JustifyContent::Center,
                                margin: UiRect::vertical(Val::Px(40.0)),
                                align_items: AlignItems::Center,
                                ..default()
                            }),
                        GenerationCountLabel,
                    ));
                    parent.spawn((
                        TextBundle::from_section("Score:", text_style.clone())
                            .with_text_alignment(TextAlignment::Center)
                            .with_style(Style {
                                flex_direction: FlexDirection::Row,
                                justify_content: JustifyContent::Center,
                                margin: UiRect::vertical(Val::Px(40.0)),
                                ..default()
                            }),
                        MaxScoreLabel,
                    ));
                    parent.spawn((
                        TextBundle::from_section("Cars:", text_style.clone())
                            .with_text_alignment(TextAlignment::Center)
                            .with_style(Style {
                                flex_direction: FlexDirection::Row,
                                justify_content: JustifyContent::Center,
                                margin: UiRect::vertical(Val::Px(40.0)),
                                ..default()
                            }),
                        CarsAliveLabel,
                    ));
                });
        });
    // Car icon
    commands.spawn((
        ImageBundle {
            image: asset_server.load("car-icon.png").into(),
            z_index: ZIndex::Global(2),
            style: Style {
                position_type: PositionType::Absolute,
                size: Size::height(Val::Px(40.0)),
                position: UiRect {
                    bottom: Val::Percent(2.0),
                    left: Val::Percent(22.3),
                    ..default()
                },
                align_self: AlignSelf::Center,
                ..default()
            },
            ..default()
        },
        CarProgressIcon,
    ));
}

fn stats_dialog_system(
    mut contexts: EguiContexts,
    sim_stats: Res<SimStats>,
    mut settings: ResMut<Settings>,
) {
    let ctx = contexts.ctx_mut();

    egui::Window::new("no-title")
        .title_bar(false)
        .min_width(200.0)
        .default_pos(egui::pos2(1800.0, 1000.0))
        .show(ctx, |ui| {
            egui::CollapsingHeader::new("Distance Travelled")
                .default_open(true)
                .show(ui, |ui| {
                    let fitness_curve: PlotPoints = (0..sim_stats.fitness.len())
                        .map(|i| [i as f64, sim_stats.fitness[i] as f64])
                        .collect();
                    let line = Line::new(fitness_curve);
                    Plot::new("fitness_curve")
                        .view_aspect(2.0)
                        .show(ui, |plot_ui| plot_ui.line(line));
                });

            egui::CollapsingHeader::new("Settings")
                .default_open(true)
                .show(ui, |ui| {
                    ui.checkbox(&mut settings.is_show_rays, "Ray casts");
                    ui.checkbox(
                        &mut settings.is_hide_rays_at_start,
                        "Hide ray casts at start",
                    );
                    ui.checkbox(&mut settings.is_camera_follow, "Camera follow");
                });

            egui::CollapsingHeader::new("Controls")
                .default_open(true)
                .show(ui, |ui| {
                    if ui.button("Start next generation").clicked() {
                        settings.start_next_generation = true;
                    };
                    if ui.button("Restart Simulation").clicked() {
                        settings.restart_sim = true;
                    };
                });
        });
}

fn nn_viz_system(mut contexts: EguiContexts, best_brain: Res<BrainToDisplay>) {
    if best_brain.0.is_empty() {
        return;
    }

    let ctx = contexts.ctx_mut();
    let mut shapes = Vec::new();
    let tot_height = 700.0;

    // NN viz points
    let points1 = get_nn_viz_points(NUM_RAY_CASTS as usize, tot_height - 100.0);
    let points2 = get_nn_viz_points(NUM_HIDDEN_NODES as usize, tot_height);
    let points3 = get_nn_viz_points(NUM_OUPUT_NODES as usize, tot_height - 300.0);
    // NN ouput
    let values1 = best_brain.0[0].clone();
    let values2 = best_brain.0[1].clone();
    let values3 = best_brain.0[2].clone();
    // x's
    let x1 = 75.0;
    let x2 = 225.0;
    let x3 = 375.0;
    // Padding
    let padding1 = 100.0;
    let padding2 = 50.0;
    let padding3 = 200.0;
    // colors
    let colors1: Vec<Color32> = values1
        .iter()
        .rev()
        .map(|v| {
            if *v != 1.0 {
                Color32::GREEN
            } else {
                Color32::RED
            }
        })
        .collect();
    let colors2: Vec<Color32> = values2
        .iter()
        .rev()
        .map(|v| {
            if *v > 0.5 {
                Color32::GREEN
            } else {
                Color32::RED
            }
        })
        .collect();
    let mut colors3 = vec![Color32::RED, Color32::RED, Color32::RED];
    if values3[1] >= 0.5 {
        colors3[0] = Color32::GREEN;
    } else {
        colors3[1] = Color32::GREEN;
    }

    // if values3[0] >= NN_W_ACTIVATION_THRESHOLD {
    //     colors3[0] = Color32::GREEN;
    // }
    // if values3[2] >= NN_S_ACTIVATION_THRESHOLD {
    //     colors3[2] = Color32::GREEN;
    // }

    // layer 1 -> 2 lines
    for (p1, c1) in points1.iter().zip(colors1.iter()) {
        for (p2, c2) in points2.iter().zip(colors2.iter()) {
            let mut color = Color32::RED;
            if are_colors_equad(*c1, *c2) {
                color = Color32::GREEN;
            }
            shapes.push(egui::Shape::line(
                vec![pos2(x1, *p1 + padding1), pos2(x2, *p2 + padding2)],
                Stroke { width: 0.3, color },
            ));
        }
    }

    // layer 2 -> 3 lines
    for (p2, c2) in points2.iter().zip(colors2.iter()) {
        for (p3, c3) in points3.iter().zip(colors3.iter()) {
            let mut color = Color32::RED;
            if are_colors_equad(*c2, *c3) {
                color = Color32::GREEN;
            }
            shapes.push(egui::Shape::line(
                vec![pos2(x2, *p2 + padding2), pos2(x3, *p3 + padding3)],
                Stroke { width: 0.3, color },
            ));
        }
    }

    // layer 1
    for (p, c) in points1.iter().zip(colors1.iter()) {
        shapes.push(get_nn_node_shape(x1, *p + padding1, *c));
    }
    // layer 2
    for (p, c) in points2.iter().zip(colors2.iter()) {
        shapes.push(get_nn_node_shape(x2, *p + padding2, *c));
    }
    // layer 3
    for (p, c) in points3.iter().zip(colors3.iter()) {
        shapes.push(get_nn_node_shape(x3, *p + padding3, *c));
    }

    shapes.append(&mut arrow_keys_viz_system(colors3));
    egui::SidePanel::left("left")
        .min_width(400.0)
        .show(ctx, |ui| {
            shapes.iter().for_each(|s| {
                ui.painter().add(s.clone());
            });
        });
}

fn generation_count_stats_system(
    stats: Res<SimStats>,
    mut q_generation_text: Query<&mut Text, With<GenerationCountLabel>>,
) {
    let mut gen_text = q_generation_text.single_mut();
    gen_text.sections[0].value = format!("Gen: \n{}", stats.generation_count);
}

fn num_cars_stats_system(
    stats: Res<SimStats>,
    mut q_num_cars_text: Query<&mut Text, With<CarsAliveLabel>>,
) {
    let mut num_cars_text = q_num_cars_text.single_mut();
    num_cars_text.sections[0].value = format!("Cars: \n{}/{}", stats.num_cars_alive, NUM_AI_CARS);
}

fn max_score_stats_system(
    stats: Res<SimStats>,
    mut q_max_score_text: Query<&mut Text, With<MaxScoreLabel>>,
) {
    let mut max_score_text = q_max_score_text.single_mut();
    max_score_text.sections[0].value = format!("Score: \n{}", stats.max_current_score as u32);
}

fn car_progress_system(
    stats: Res<SimStats>,
    mut q_car_icon: Query<&mut Style, With<CarProgressIcon>>,
) {
    let mut style = q_car_icon.single_mut();
    style.position.bottom = Val::Percent(stats.max_current_score - 3.0);
}

fn arrow_keys_viz_system(colors: Vec<Color32>) -> Vec<Shape> {
    // wasd buttons
    let x = 75.0;
    let y = 800.0;
    let mut shapes = Vec::new();

    // w
    shapes.push(egui::Shape::rect_filled(
        egui::Rect {
            min: egui::pos2(100.0 + x, 100.0 + y),
            max: egui::pos2(150.0 + x, 150.0 + y),
        },
        10.0,
        Color32::GREEN,
    ));
    // a
    shapes.push(egui::Shape::rect_filled(
        egui::Rect {
            min: egui::pos2(40.0 + x, 160.0 + y),
            max: egui::pos2(90.0 + x, 210.0 + y),
        },
        10.0,
        colors[0],
    ));
    // s
    shapes.push(egui::Shape::rect_filled(
        egui::Rect {
            min: egui::pos2(100.0 + x, 160.0 + y),
            max: egui::pos2(150.0 + x, 210.0 + y),
        },
        10.0,
        Color32::RED,
    ));
    // d
    shapes.push(egui::Shape::rect_filled(
        egui::Rect {
            min: egui::pos2(160.0 + x, 160.0 + y),
            max: egui::pos2(210.0 + x, 210.0 + y),
        },
        10.0,
        colors[1],
    ));

    shapes
}

fn get_nn_node_shape(x: f32, y: f32, color: Color32) -> egui::Shape {
    egui::Shape::Circle(CircleShape {
        center: (x, y).into(),
        radius: NN_VIZ_NODE_RADIUS,
        fill: color,
        stroke: Stroke {
            width: 1.0,
            color: Color32::WHITE,
        },
    })
}

fn get_nn_viz_points(n: usize, tot_size: f32) -> Vec<f32> {
    let point_spacing = tot_size / (n - 1) as f32;
    let mut points = Vec::new();

    for i in 0..n {
        let x = i as f32 * point_spacing;
        points.push(x);
    }

    points
}

fn are_colors_equad(first: Color32, second: Color32) -> bool {
    (first.g() == 255 && second.g() == 255) || (first.r() == 255 && second.r() == 255)
}
