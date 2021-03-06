/*
* Box2D.XNA port of Box2D:
* Copyright (c) 2009 Brandon Furtwangler, Nathan Furtwangler
*
* Original source Box2D:
* Copyright (c) 2006-2009 Erin Catto http://www.gphysics.com
*
* This software is provided 'as-is', without any express or implied
* warranty.  In no event will the authors be held liable for any damages
* arising from the use of this software.
* Permission is granted to anyone to use this software for any purpose,
* including commercial applications, and to alter it and redistribute it
* freely, subject to the following restrictions:
* 1. The origin of this software must not be misrepresented; you must not
* claim that you wrote the original software. If you use this software
* in a product, an acknowledgment in the product documentation would be
* appreciated but is not required.
* 2. Altered source versions must be plainly marked as such, and must not be
* misrepresented as being the original software.
* 3. This notice may not be removed or altered from any source distribution.
*/

namespace Uno.Physics.Box2D
{
    public class ContactManager
    {
        internal ContactManager()
        {
            _addPair = AddPair;

            _contactList = null;
            _contactCount = 0;
            ContactFilter = new DefaultContactFilter();
            ContactListener = new DefaultContactListener();
        }

	    // Broad-phase callback.
        internal void AddPair(FixtureProxy proxyA, FixtureProxy proxyB)
        {
            Fixture fixtureA = proxyA.fixture;
            Fixture fixtureB = proxyB.fixture;

            int indexA = proxyA.childIndex;
            int indexB = proxyB.childIndex;

	        Body bodyA = fixtureA.GetBody();
	        Body bodyB = fixtureB.GetBody();

	        // Are the fixtures on the same body?
	        if (bodyA == bodyB)
	        {
		        return;
	        }

	        // Does a contact already exist?
	        ContactEdge edge = bodyB.GetContactList();
	        while (edge != null)
	        {
		        if (edge.Other == bodyA)
		        {
			        Fixture fA = edge.Contact.GetFixtureA();
			        Fixture fB = edge.Contact.GetFixtureB();
                    int iA = edge.Contact.GetChildIndexA();
                    int iB = edge.Contact.GetChildIndexB();

                    if (fA == fixtureA && fB == fixtureB && iA == indexA && iB == indexB)
                    {
                        // A contact already exists.
                        return;
                    }

                    if (fA == fixtureB && fB == fixtureA && iA == indexB && iB == indexA)
                    {
				        // A contact already exists.
				        return;
			        }
		        }

		        edge = edge.Next;
	        }

            // Does a joint override collision? Is at least one body dynamic?
            if (bodyB.ShouldCollide(bodyA) == false)
	        {
		        return;
	        }

	        // Check user filtering.
            if (ContactFilter != null && ContactFilter.ShouldCollide(fixtureA, fixtureB) == false)
	        {
		        return;
	        }

	        // Call the factory.
	        Contact c = Contact.Create(fixtureA, indexA, fixtureB, indexB);

	        // Contact creation may swap fixtures.
	        fixtureA = c.GetFixtureA();
	        fixtureB = c.GetFixtureB();
            indexA = c.GetChildIndexA();
            indexB = c.GetChildIndexB();
	        bodyA = fixtureA.GetBody();
	        bodyB = fixtureB.GetBody();

	        // Insert into the world.
	        c._prev = null;
	        c._next = _contactList;
	        if (_contactList != null)
	        {
		        _contactList._prev = c;
	        }
	        _contactList = c;

	        // Connect to island graph.

	        // Connect to body A
	        c._box2dNodeA.Contact = c;
	        c._box2dNodeA.Other = bodyB;

	        c._box2dNodeA.Prev = null;
	        c._box2dNodeA.Next = bodyA._contactList;
	        if (bodyA._contactList != null)
	        {
		        bodyA._contactList.Prev = c._box2dNodeA;
	        }
	        bodyA._contactList = c._box2dNodeA;

	        // Connect to body B
	        c._box2dNodeB.Contact = c;
	        c._box2dNodeB.Other = bodyA;

	        c._box2dNodeB.Prev = null;
	        c._box2dNodeB.Next = bodyB._contactList;
	        if (bodyB._contactList != null)
	        {
		        bodyB._contactList.Prev = c._box2dNodeB;
	        }
	        bodyB._contactList = c._box2dNodeB;

	        ++_contactCount;
        }

	    internal void FindNewContacts()
        {
            _broadPhase.UpdatePairs<FixtureProxy>(_addPair);
        }

	    internal void Destroy(Contact c)
        {
            Fixture fixtureA = c.GetFixtureA();
	        Fixture fixtureB = c.GetFixtureB();
	        Body bodyA = fixtureA.GetBody();
	        Body bodyB = fixtureB.GetBody();

            if (ContactListener != null && c.IsTouching())
	        {
		        ContactListener.EndContact(c);
	        }

	        // Remove from the world.
	        if (c._prev != null)
	        {
		        c._prev._next = c._next;
	        }

            if (c._next != null)
	        {
		        c._next._prev = c._prev;
	        }

	        if (c == _contactList)
	        {
		        _contactList = c._next;
	        }

	        // Remove from body 1
            if (c._box2dNodeA.Prev != null)
	        {
		        c._box2dNodeA.Prev.Next = c._box2dNodeA.Next;
	        }

            if (c._box2dNodeA.Next != null)
	        {
		        c._box2dNodeA.Next.Prev = c._box2dNodeA.Prev;
	        }

	        if (c._box2dNodeA == bodyA._contactList)
	        {
		        bodyA._contactList = c._box2dNodeA.Next;
	        }

	        // Remove from body 2
            if (c._box2dNodeB.Prev != null)
	        {
		        c._box2dNodeB.Prev.Next = c._box2dNodeB.Next;
	        }

            if (c._box2dNodeB.Next != null)
	        {
		        c._box2dNodeB.Next.Prev = c._box2dNodeB.Prev;
	        }

	        if (c._box2dNodeB == bodyB._contactList)
	        {
		        bodyB._contactList = c._box2dNodeB.Next;
	        }

            c.Destroy();

	        --_contactCount;
        }

	    internal void Collide()
        {
            // Update awake contacts.
	        Contact c = _contactList;
	        while (c != null)
	        {
		        Fixture fixtureA = c.GetFixtureA();
		        Fixture fixtureB = c.GetFixtureB();
                int indexA = c.GetChildIndexA();
                int indexB = c.GetChildIndexB();
		        Body bodyA = fixtureA.GetBody();
		        Body bodyB = fixtureB.GetBody();

		        if (bodyA.IsAwake() == false && bodyB.IsAwake() == false)
		        {
			        c = c.GetNext();
			        continue;
		        }

		        // Is this contact flagged for filtering?
                if ((c._flags & ContactFlags.Filter) == ContactFlags.Filter)
		        {
                    // Should these bodies collide?
                    if (bodyB.ShouldCollide(bodyA) == false)
			        {
				        Contact cNuke = c;
				        c = cNuke.GetNext();
				        Destroy(cNuke);
				        continue;
			        }

			        // Check user filtering.
                    if (ContactFilter != null && ContactFilter.ShouldCollide(fixtureA, fixtureB) == false)
			        {
				        Contact cNuke = c;
				        c = cNuke.GetNext();
				        Destroy(cNuke);
				        continue;
			        }

			        // Clear the filtering flag.
			        c._flags &= ~ContactFlags.Filter;
		        }

                int proxyIdA = fixtureA._proxies[indexA].proxyId;
                int proxyIdB = fixtureB._proxies[indexB].proxyId;

                bool overlap = _broadPhase.TestOverlap(proxyIdA, proxyIdB);

                // Here we destroy contacts that cease to overlap in the broad-phase.
                if (overlap == false)
		        {
			        Contact cNuke = c;
			        c = cNuke.GetNext();
			        Destroy(cNuke);
			        continue;
		        }

		        // The contact persists.
		        c.Update(ContactListener);
		        c = c.GetNext();
	        }
        }

	    internal BroadPhase _broadPhase = new BroadPhase();
	    internal Contact _contactList;
	    internal int _contactCount;

        internal IContactFilter ContactFilter { get; set; }
        internal IContactListener ContactListener { get; set; }

        Uno.Action<FixtureProxy, FixtureProxy> _addPair;
    }
}
