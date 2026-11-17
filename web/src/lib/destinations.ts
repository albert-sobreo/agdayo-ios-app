/** The sign-in screen's rotating destinations, from the original Agdayo web app. */
export interface Destination {
  key: string
  name: string
  lead: string
  color: string
  shadow: string
  description: string
  credits: string
}

export const destinations: Destination[] = [
  {
    key: 'elnido', name: 'El Nido', lead: 'Plan your trip to', color: '#F2FF67', shadow: '#828c22',
    description: 'A tropical paradise with crystal-clear waters, limestone cliffs and pristine beaches. Perfect for island hopping, diving and exploring hidden lagoons.',
    credits: 'El Nido, Palawan. Photo by Eibner Saliba',
  },
  {
    key: 'manila', name: 'Manila', lead: 'Plan your trip to', color: '#F8B02B', shadow: '#936203',
    description: 'The bustling capital, full of history, culture and energy. From the walls of Intramuros to street art, food and nightlife, it’s an unforgettable city adventure.',
    credits: 'Manila. Photo by Michael Buillerey',
  },
  {
    key: 'baguio', name: 'Baguio', lead: 'Plan your trip to', color: '#F8B02B', shadow: '#936203',
    description: 'The Summer Capital of the Philippines: cool weather, pine forests, gardens and a lively arts scene. A refreshing escape for nature lovers and foodies.',
    credits: 'Baguio, Benguet. Photo by Gian Paul Guinto',
  },
  {
    key: 'makati', name: 'Makati', lead: 'Plan your trip to', color: '#FFFFFF', shadow: '#a2a2a2',
    description: 'The heart of Metro Manila, known for its nightlife, shopping and skyline. Sleek towers, big malls and a thriving food scene.',
    credits: 'Makati, Metro Manila. Photo by JC Gellidon',
  },
  {
    key: 'subic', name: 'Subic', lead: 'Plan your trip to', color: '#C6FB9F', shadow: '#82ad62',
    description: 'A coastal gem with clean beaches, water sports and family-friendly attractions. Adventure and relaxation in one weekend.',
    credits: 'Subic, Zambales. Photo by pixmike',
  },
  {
    key: 'cebu', name: 'Cebu', lead: 'Discover the Queen City of the South', color: '#FFEF95', shadow: '#988f59',
    description: 'Historic sites, stunning islands and rich culture. From city life to beaches and dive spots, there’s something for every traveler.',
    credits: 'Cebu City, Cebu. Photo by Angelyn Sanjorjo',
  },
  {
    key: 'siargao', name: 'Siargao', lead: 'Ride the waves in paradise', color: '#00FFA6', shadow: '#129365',
    description: 'The surfing capital of the Philippines, with world-class waves, turquoise lagoons, hidden caves and laid-back island days.',
    credits: 'Guyam Island, Siargao. Photo by Rene Padillo',
  },
  {
    key: 'batanes', name: 'Batanes', lead: 'Experience rugged beauty and rolling hills', color: '#FCAA30', shadow: '#704c15',
    description: 'Dramatic cliffs, rolling hills, stone houses and the warm Ivatan people, in the northernmost province of the Philippines.',
    credits: 'Batanes. Photo by JR Padlan',
  },
]
