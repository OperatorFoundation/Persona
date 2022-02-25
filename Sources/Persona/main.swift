
import Foundation
import Spacetime
import Simulation

func main()
{
    let simulation = Simulation(capabilities: Capabilities(display: true, networkConnect: true, networkListen: true))
    let universe = Persona(effects: simulation.effects, events: simulation.events)

    let lock = DispatchGroup()

    Task
    {
        lock.enter()
        try await universe.run()
        lock.leave()
    }

    lock.wait()
}

main()
