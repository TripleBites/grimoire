# Research Topics:

### Category 1: Make the boundary non-linear
- MLP / sigmoid, tanh, ReLU neurons
- Kernel perceptron / SVM
- RBF networks

### Category 2: Different algebraic primitives
- Hyperdimensional Computing / VSA neurons
- Tsetlin Machines
- Spiking neurons (LIF, Izhikevich)
- Ternary/binary weight neurons (BitNet-style)

### Category 3: Different learning rules on the same primitive
- Hebbian learning
- Widrow-Hoff / Adaline / delta rule (historical bridge between the perceptron and backprop)


### Category 4: New primitive
If you want to reinvent the wheel rather than reshuffle known parts, the actual open mathematical design space is:

1. What's the elementary operation? (dot product / distance / Boolean conjunction / binding operation / resonance)
2. What's the nonlinearity/decision rule? (threshold / radial falloff / winner-take-all / automaton state transition)
3. What's the learning rule, and is it local? (global backprop needs a full forward+backward pass — disqualifying for true real-time; local rules like Hebbian, STDP, and Tsetlin's automaton updates are what actually make online learning cheap)

# Real Neurons vs Neural Network Perceptron

Real neurons accumulate charge over time until a threshold is met. The it fires. Perceptron ignores relitive spike timing or phase of an incoming signal, and considers only the frequency of the firing between neurons.

Biological neurons are EXTREMELY SLOW.

This is a critical and difference. Biological neurons allow for single spikes to have meaning. Rather then having a spike "train" represent a value (like in MLP). As the overwhelmming majority of the brains neurons only spike realy. So many neurons propbly do have specific meaning. This differes from MPL where entire layers our neurons chains represent meaning. We need a more condensed model of the neuron, that contains local memory. this SHOULD help with neuroplasticity of the model.

How to encode numerical values:
1. The friquency of the spikes in the single signal
2. The timming of spikes in a single signal
3. Some encoding of parallel signals


**Referances:**
- https://www.youtube.com/watch?v=KQP1gPTk0FI&t=741s (Machine Learning Is Not Like Your Brain - FULL SERIES - Future AI Society)
- https://www.youtube.com/watch?v=ilp3ZHTKPNg (
Building a Perceptron From SCRATCH (no frameworks, only math and python) - The Origins of AI - Ep.1 - Digital Mirror)
- https://www.youtube.com/watch?v=zOmhHE2xctw (
The Core Equation Of Neuroscience - Artem Kirsanov)
- https://www.youtube.com/watch?v=gLtGVEhMFN4 (
Why Two Identical Neurons Behave Differently - Artem Kirsanov)

