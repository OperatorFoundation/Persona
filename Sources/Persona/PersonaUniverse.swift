//
//  Persona.swift
//  
//
//  Created by Dr. Brandon Wiley on 2/24/22.
//

import Universe

public class PersonaUniverse: Universe<Int>
{
    public override func main() throws
    {
        let listener = try listen("127.0.0.1", 1234)
        let connection = listener.accept()
        let r = random()
        connection.write(data: r.data)
        let result = connection.read(size: 4)
        display(result.string)
        display("done")
    }
}
