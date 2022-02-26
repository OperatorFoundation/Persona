
import Foundation
import Spacetime
import Simulation

func main()
{
    let simulation = Simulation(capabilities: Capabilities(display: true, networkConnect: true, networkListen: true))
    let universe = Persona(effects: simulation.effects, events: simulation.events)

    do
    {
        try universe.run()
    }
    catch
    {
        print(error)
    }
}

main()
