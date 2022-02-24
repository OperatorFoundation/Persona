import Simulation

let simulation = Simulation()
let universe = PersonaUniverse(effects: simulation.effects, events: simulation.events)
try universe.run()
