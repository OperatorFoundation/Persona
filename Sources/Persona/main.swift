
import Foundation
import Spacetime
import Simulation

// run in one XCode window while you run the flower test in another
func main()
{
    let simulation = Simulation(capabilities: Capabilities(.display, .networkConnect, .networkListen))
    // effects are outputs
    // events are inputs
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
