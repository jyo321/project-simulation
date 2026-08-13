import { Component } from '@angular/core';
import { RouterLink, RouterOutlet } from '@angular/router';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, RouterLink],
  template: `
    <nav>
      <a routerLink="/apply">Northbridge Lending — Apply</a>
    </nav>
    <router-outlet></router-outlet>
  `,
})
export class AppComponent {}
