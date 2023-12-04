use rand::Rng;
use bincode2;
use serde::{Deserialize, Serialize};

const BRAIN_MUTATION_RATE: f32 = 5.0;
const BRAIN_MUTATION_VARIATION: f32 = 0.25;

#[derive(Clone, Serialize, Deserialize, Default, Debug)]
pub struct Net {
    n_inputs: usize,
    layers: Vec<Layer>,
}

#[derive(Clone, Serialize, Deserialize,Default, Debug)]
struct Layer {
    nodes: Vec<Vec<f64>>,
}

impl Net {
    pub fn clone_layers(&self) -> Vec<Layer> {
        self.layers.clone()
    }
    pub fn is_empty(&self) -> bool {
        self.layers.is_empty()
    }
    pub fn save_brain(brain: &[Vec<f64>]) -> Self {
        let mut layers = Vec::new();
        let mut prev_layer_size = brain[0].len();
        for layer in brain.iter() {
            let layer_size = layer.len();
            layers.push(Layer::new(layer_size, prev_layer_size));
            prev_layer_size = layer_size;
        }

        Self {
            layers,
            n_inputs: brain[0].len(),
        }
    }
    pub fn save_net(&self, path: &str) {
        let mut file = std::fs::File::create(path).unwrap();
        bincode2::serialize_into(&mut file, self).unwrap();
    }
    pub fn load_net(sample: &Self, layer_sizes: &[usize], path: &str) -> Result<Self,Self> {
        match std::fs::File::open(path) {
            Ok(file) => {
                let res:Net = bincode2::deserialize_from(file).unwrap();
                if !res.is_same_shape(sample) {
                    println!("saved file shape mismatch");
                    Err(Self::new(layer_sizes))
                } else {
                    Ok(res)
                }
            },
            Err(_) => Err(Self::new(layer_sizes)),
        }
    }

    pub fn is_same_shape(&self, sample: &Self) -> bool {
        if sample.layers.len() != self.layers.len() {
            println!("mismatch at shape.len {} v.s. {}", sample.layers.len(), self.layers.len());
            return false;
        }

        for (i, &ref layer) in sample.layers.iter().enumerate() {
            let size = layer.nodes.len();
            if size != self.layers[i].nodes.len() {
                println!("mismatch at layer {i} old_size:{} new_size: {size}", self.layers[i].nodes.len());
                return false;
            }
        }

        true
    }
    pub fn new(layer_sizes: &[usize]) -> Self {
        if layer_sizes.len() < 2 {
            panic!("Need at least 2 layers");
        }
        for &size in layer_sizes.iter() {
            if size < 1 {
                panic!("Empty layers not allowed");
            }
        }

        let mut layers = Vec::new();
        let first_layer_size = *layer_sizes.first().unwrap();
        let mut prev_layer_size = first_layer_size;

        for &layer_size in layer_sizes[1..].iter() {
            layers.push(Layer::new(layer_size, prev_layer_size));
            prev_layer_size = layer_size;
        }

        Self {
            layers,
            n_inputs: first_layer_size,
        }
    }

    pub fn predict(&self, inputs: &Vec<f64>) -> Vec<Vec<f64>> {
        if inputs.len() != self.n_inputs {
            panic!("Bad input size");
        }

        let mut outputs = Vec::new();
        outputs.push(inputs.clone());
        for (layer_index, layer) in self.layers.iter().enumerate() {
            let layer_results = layer.predict(&outputs[layer_index]);
            outputs.push(layer_results);
        }

        outputs
    }

    pub fn mutate(&mut self) {
        self.layers.iter_mut().for_each(|l| l.mutate());
    }
}

impl Layer {
    fn new(layer_size: usize, prev_layer_size: usize) -> Self {
        let mut rng = rand::thread_rng();
        let mut nodes: Vec<Vec<f64>> = Vec::new();

        for _ in 0..layer_size {
            let mut node: Vec<f64> = Vec::new();
            for _ in 0..prev_layer_size + 1 {
                let random_weight: f64 = rng.gen_range(-1.0f64..1.0f64);
                node.push(random_weight);
            }
            nodes.push(node);
        }

        Self { nodes }
    }

    fn predict(&self, inputs: &Vec<f64>) -> Vec<f64> {
        let mut layer_results = Vec::new();
        for node in self.nodes.iter() {
            let out_node = self.dot_prod(&node, &inputs);
            //let pred = self.sigmoid(out_node);
            let pred = self.relu(out_node);
            layer_results.push(pred);
        }

        layer_results
    }

    fn mutate(&mut self) {
        let mut rng = rand::thread_rng();
        for n in self.nodes.iter_mut() {
            for val in n.iter_mut() {
                if rng.gen_range(0.0..1.0) >= BRAIN_MUTATION_RATE {
                    continue;
                }

                *val += rng.gen_range(-BRAIN_MUTATION_VARIATION..BRAIN_MUTATION_VARIATION) as f64;
            }
        }
    }

    fn relu(&self, y: f64) -> f64 {
        y.clamp(0.0, 1.0)
    }

    fn dot_prod(&self, node: &Vec<f64>, values: &Vec<f64>) -> f64 {
        let mut it = node.iter();
        let mut total = *it.next().unwrap();
        for (weight, value) in it.zip(values.iter()) {
            total += weight * value;
        }

        total
    }

    fn sigmoid(&self, y: f64) -> f64 {
        1f64 / (1f64 + (-y).exp())
    }
}
