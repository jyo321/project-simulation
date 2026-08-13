import { Routes } from '@angular/router';
import { ApplyComponent } from './pages/apply/apply.component';
import { UploadDocumentsComponent } from './pages/upload-documents/upload-documents.component';
import { TrackStatusComponent } from './pages/track-status/track-status.component';

export const routes: Routes = [
  { path: '', redirectTo: 'apply', pathMatch: 'full' },
  { path: 'apply', component: ApplyComponent },
  { path: 'applications/:id/documents', component: UploadDocumentsComponent },
  { path: 'applications/:id/status', component: TrackStatusComponent },
];
