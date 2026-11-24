#include <grimoire/grimoire.hpp>
#include <grimoire/nn.hpp>

#include <vector>

#define NN_BACKPROP_TRADITIONAL 1
#include <cstddef>
#include <iostream>

int main() {
  nn::Matrix train_data(4, 3, 0.0f);
  float data[4][3] = {{0, 0, 0}, {1, 0, 1}, {0, 1, 1}, {1, 1, 0}};

  for (size_t i = 0; i < 4; ++i) {
    for (size_t j = 0; j < 3; ++j) {
      train_data(i, j) = data[i][j];
    }
  }
  train_data.print("XOR training data");

  std::vector<size_t> arch = {2, 4, 1};
  nn::NeuralNetwork xor_nn(arch);

  xor_nn.randomize(-2.0f, 2.0f);

  size_t epochs = 500000;
  float learning_rate = 0.5f;
  const size_t print_every = 1000;

  nn::Batch batch;

  size_t batch_size = 1;

  std::cout << "\nTraining started...\n";

  for (size_t i = 0; i < epochs; i++) {
    do {
      batch.process(batch_size, xor_nn, train_data, learning_rate);
    } while (!batch.finished);

    if (i % print_every == 0) {
      std::cout << "Epoch " << i << " | Cost: " << xor_nn.cost(train_data)
                << "\n";
    }
  }

  std::cout << "\nPredictions after training:\n";
  std::cout << "-------------------------------\n";
  for (size_t i = 0; i < 4; ++i) {
    xor_nn.get_input()(0, 0) = train_data(i, 0);
    xor_nn.get_input()(0, 1) = train_data(i, 1);
    xor_nn.forward();
    float pred = xor_nn.get_output()(0, 0);
    float target = train_data(i, 2);
    std::cout << train_data(i, 0) << " XOR " << train_data(i, 1) << " -> "
              << pred << "    (target: " << target << ")\n";
  }

  return 0;
}